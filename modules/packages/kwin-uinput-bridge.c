// Bridge Sunshine's virtual uinput devices into KWin via org_kde_kwin_fake_input.
//
// Why this exists: Sunshine injects input only through uinput (inputtino), which
// requires a compositor that reads those devices back through libinput. KWin's
// virtual backend never creates a libinput backend -- VirtualBackend does not
// override createInputBackend() -- so on a headless `kwin_wayland --virtual`
// session Sunshine's mouse and keyboard have no reader at all. KWin does always
// add a FakeInputBackend (see kwin src/input.cpp, setupInputBackends), so the
// org_kde_kwin_fake_input protocol is the one input path that exists here.
//
// This reads the Sunshine-created evdev nodes and replays them as fake_input
// requests. Gamepads are deliberately skipped: games open evdev directly, so
// they need device permissions rather than compositor injection.
//
// org_kde_kwin_fake_input is a privileged interface. KWin only hands it to a
// client whose /proc/<pid>/exe matches the Exec of an installed desktop file
// declaring X-KDE-Wayland-Interfaces. This binary is therefore installed
// unwrapped, so that path is stable.

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <libevdev/libevdev.h>
#include <linux/input.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <unistd.h>
#include <wayland-client.h>

#include "fake-input-client-protocol.h"

// Device names, from Sunshine's src/platform/linux/input/inputtino_common.h:
// every device is named via inputtino_name_for_seat(), which appends " (<seat>)"
// only when XDG_SEAT is set and is not seat0. The Stream Session is a lingering
// user with no seat at all, so the names arrive unsuffixed:
//
//   "Mouse passthrough"  "Keyboard passthrough"  "Touch passthrough"  "Pen passthrough"
//   "Sunshine X-Box One (virtual) pad"  (+ Nintendo, PS5)
//
// Only the gamepads carry a "Sunshine" prefix -- which is why matching on that
// prefix caught exactly the devices this bridge skips and none of the ones it
// exists to carry. Prefix matching keeps working if a seat suffix ever appears.
static const char *const DEVICE_PREFIXES[] = {
    "Mouse passthrough",
    "Keyboard passthrough",
    "Touch passthrough",
    "Pen passthrough",
};
#define MAX_DEVICES 32
// One wheel detent. libinput reports 15 logical pixels per detent; matching it
// keeps scroll speed consistent with a session that has a real pointer.
#define SCROLL_STEP 15.0

struct device {
    int fd;
    struct libevdev *evdev;
    char node[PATH_MAX];
    bool absolute;  // reports ABS_X/ABS_Y rather than REL_X/REL_Y
    int abs_min_x, abs_max_x, abs_min_y, abs_max_y;
    // Accumulated within one SYN_REPORT frame.
    double rel_dx, rel_dy;
    bool have_rel;
    int abs_x, abs_y;
    bool have_abs;
};

static struct wl_display *display;
static struct org_kde_kwin_fake_input *fake_input;
static uint32_t fake_input_version;
static struct device devices[MAX_DEVICES];
static int device_count;
static int output_width = 1920;
static int output_height = 1080;

static bool is_pointer_button(unsigned int code)
{
    // BTN_MOUSE (0x110) .. BTN_TASK (0x117) are the pointer buttons KWin
    // expects on the fake_input button request; everything else that arrives
    // as EV_KEY is treated as a keyboard key.
    return code >= BTN_MOUSE && code <= BTN_TASK;
}

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version)
{
    if (strcmp(interface, "org_kde_kwin_fake_input") == 0) {
        // keyboard_key arrived in version 4; without it this bridge can move
        // the pointer but never type, which is not worth running.
        uint32_t bind_version = version > 4 ? 4 : version;
        fake_input_version = bind_version;
        fake_input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface,
                                      bind_version);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static bool already_open(const char *node)
{
    for (int i = 0; i < device_count; i++) {
        if (strcmp(devices[i].node, node) == 0) {
            return true;
        }
    }
    return false;
}

static void try_open_device(const char *node)
{
    if (device_count >= MAX_DEVICES || already_open(node)) {
        return;
    }

    int fd = open(node, O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        return;  // Not ours, or not readable yet; the udev rule scopes this.
    }

    struct libevdev *evdev = NULL;
    if (libevdev_new_from_fd(fd, &evdev) < 0) {
        close(fd);
        return;
    }

    const char *name = libevdev_get_name(evdev);
    bool wanted = false;
    for (size_t i = 0; name && i < sizeof(DEVICE_PREFIXES) / sizeof(DEVICE_PREFIXES[0]); i++) {
        if (strncmp(name, DEVICE_PREFIXES[i], strlen(DEVICE_PREFIXES[i])) == 0) {
            wanted = true;
            break;
        }
    }
    if (!wanted) {
        libevdev_free(evdev);
        close(fd);
        return;
    }

    // Gamepads are read directly by games; injecting them through the
    // compositor would be wrong as well as unsupported by fake_input.
    if (libevdev_has_event_code(evdev, EV_KEY, BTN_GAMEPAD)) {
        fprintf(stderr, "bridge: ignoring gamepad '%s' (games read evdev directly)\n", name);
        libevdev_free(evdev);
        close(fd);
        return;
    }

    struct device *d = &devices[device_count];
    memset(d, 0, sizeof(*d));
    d->fd = fd;
    d->evdev = evdev;
    snprintf(d->node, sizeof(d->node), "%s", node);
    d->absolute = libevdev_has_event_code(evdev, EV_ABS, ABS_X) &&
                  libevdev_has_event_code(evdev, EV_ABS, ABS_Y);
    if (d->absolute) {
        d->abs_min_x = libevdev_get_abs_minimum(evdev, ABS_X);
        d->abs_max_x = libevdev_get_abs_maximum(evdev, ABS_X);
        d->abs_min_y = libevdev_get_abs_minimum(evdev, ABS_Y);
        d->abs_max_y = libevdev_get_abs_maximum(evdev, ABS_Y);
        if (d->abs_max_x <= d->abs_min_x || d->abs_max_y <= d->abs_min_y) {
            d->absolute = false;  // Degenerate range; fall back to relative.
        }
    }
    device_count++;
    fprintf(stderr, "bridge: attached '%s' (%s, %s)\n", name, node,
            d->absolute ? "absolute" : "relative");
}

static void scan_devices(void)
{
    DIR *dir = opendir("/dev/input");
    if (!dir) {
        return;
    }
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "event", 5) != 0) {
            continue;
        }
        char node[PATH_MAX];
        snprintf(node, sizeof(node), "/dev/input/%s", entry->d_name);
        try_open_device(node);
    }
    closedir(dir);
}

static void drop_device(int index)
{
    fprintf(stderr, "bridge: detached %s\n", devices[index].node);
    libevdev_free(devices[index].evdev);
    close(devices[index].fd);
    devices[index] = devices[device_count - 1];
    device_count--;
}

static void flush_frame(struct device *d)
{
    if (d->have_rel && (d->rel_dx != 0.0 || d->rel_dy != 0.0)) {
        org_kde_kwin_fake_input_pointer_motion(fake_input,
                                               wl_fixed_from_double(d->rel_dx),
                                               wl_fixed_from_double(d->rel_dy));
    }
    if (d->have_abs && fake_input_version >= 3) {
        double x = (double)(d->abs_x - d->abs_min_x) /
                   (double)(d->abs_max_x - d->abs_min_x) * (double)output_width;
        double y = (double)(d->abs_y - d->abs_min_y) /
                   (double)(d->abs_max_y - d->abs_min_y) * (double)output_height;
        org_kde_kwin_fake_input_pointer_motion_absolute(fake_input,
                                                        wl_fixed_from_double(x),
                                                        wl_fixed_from_double(y));
    }
    d->rel_dx = d->rel_dy = 0.0;
    d->have_rel = false;
    d->have_abs = false;
}

static void handle_event(struct device *d, const struct input_event *ev)
{
    switch (ev->type) {
    case EV_SYN:
        if (ev->code == SYN_REPORT) {
            flush_frame(d);
        }
        break;
    case EV_REL:
        if (ev->code == REL_X) {
            d->rel_dx += ev->value;
            d->have_rel = true;
        } else if (ev->code == REL_Y) {
            d->rel_dy += ev->value;
            d->have_rel = true;
        } else if (ev->code == REL_WHEEL) {
            // evdev scrolls up positive; the Wayland axis grows downward.
            org_kde_kwin_fake_input_axis(fake_input, WL_POINTER_AXIS_VERTICAL_SCROLL,
                                         wl_fixed_from_double(-ev->value * SCROLL_STEP));
        } else if (ev->code == REL_HWHEEL) {
            org_kde_kwin_fake_input_axis(fake_input, WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                                         wl_fixed_from_double(ev->value * SCROLL_STEP));
        }
        // REL_WHEEL_HI_RES is deliberately ignored: it duplicates REL_WHEEL.
        break;
    case EV_ABS:
        if (!d->absolute) {
            break;
        }
        if (ev->code == ABS_X) {
            d->abs_x = ev->value;
            d->have_abs = true;
        } else if (ev->code == ABS_Y) {
            d->abs_y = ev->value;
            d->have_abs = true;
        }
        break;
    case EV_KEY:
        if (ev->value == 2) {
            break;  // Key repeat; the compositor generates its own.
        }
        if (is_pointer_button(ev->code)) {
            org_kde_kwin_fake_input_button(fake_input, ev->code, ev->value ? 1 : 0);
        } else if (fake_input_version >= 4) {
            org_kde_kwin_fake_input_keyboard_key(fake_input, ev->code, ev->value ? 1 : 0);
        }
        break;
    default:
        break;
    }
}

static void pump_device(int index)
{
    struct device *d = &devices[index];
    struct input_event ev;
    int rc;

    do {
        rc = libevdev_next_event(d->evdev,
                                 LIBEVDEV_READ_FLAG_NORMAL | LIBEVDEV_READ_FLAG_BLOCKING,
                                 &ev);
        if (rc == LIBEVDEV_READ_STATUS_SYNC) {
            // Dropped events; resync and keep going.
            while (rc == LIBEVDEV_READ_STATUS_SYNC) {
                rc = libevdev_next_event(d->evdev, LIBEVDEV_READ_FLAG_SYNC, &ev);
            }
        } else if (rc == LIBEVDEV_READ_STATUS_SUCCESS) {
            handle_event(d, &ev);
        }
    } while (rc == LIBEVDEV_READ_STATUS_SUCCESS);

    if (rc == -ENODEV) {
        drop_device(index);
    }
}

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
            output_width = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
            output_height = atoi(argv[++i]);
        }
    }

    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "bridge: cannot connect to Wayland display (WAYLAND_DISPLAY=%s)\n",
                getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "unset");
        return 1;
    }

    // KWin advertises org_kde_kwin_fake_input only once it has finished
    // starting, and this unit is ordered merely After=graphical-session.target,
    // which says nothing about KWin being ready to answer a KService lookup.
    // Losing that race once is normal, so retry rather than exit and rely on
    // the unit's restart: an early failure would otherwise show up as a scary
    // permission error that is really just "too soon".
    for (int attempt = 0; attempt < 30 && !fake_input; attempt++) {
        if (attempt > 0) {
            sleep(2);
        }
        struct wl_registry *registry = wl_display_get_registry(display);
        wl_registry_add_listener(registry, &registry_listener, NULL);
        wl_display_roundtrip(display);
        wl_registry_destroy(registry);
    }

    if (!fake_input) {
        fprintf(stderr,
                "bridge: org_kde_kwin_fake_input not offered. It is a privileged "
                "interface: KWin only grants it to a client whose /proc/<pid>/exe "
                "matches the Exec= of an installed desktop file declaring "
                "X-KDE-Wayland-Interfaces. Check that this binary's desktop file is "
                "in XDG_DATA_DIRS and that ksycoca has been rebuilt.\n");
        return 1;
    }
    if (fake_input_version < 4) {
        fprintf(stderr, "bridge: fake_input version %u offers no keyboard_key (need >= 4)\n",
                fake_input_version);
        return 1;
    }

    org_kde_kwin_fake_input_authenticate(fake_input, "sunshine-input-bridge",
                                         "replay Sunshine's virtual input devices");

    scan_devices();

    // Sunshine creates its devices when a client connects, so watch for them.
    int inotify_fd = inotify_init1(IN_NONBLOCK);
    if (inotify_fd >= 0) {
        inotify_add_watch(inotify_fd, "/dev/input", IN_CREATE | IN_ATTRIB | IN_DELETE);
    }

    while (true) {
        struct pollfd fds[MAX_DEVICES + 2];
        int n = 0;

        wl_display_flush(display);

        fds[n].fd = wl_display_get_fd(display);
        fds[n].events = POLLIN;
        n++;
        fds[n].fd = inotify_fd;
        fds[n].events = POLLIN;
        n++;
        for (int i = 0; i < device_count; i++) {
            fds[n].fd = devices[i].fd;
            fds[n].events = POLLIN;
            n++;
        }

        if (poll(fds, n, -1) < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("bridge: poll");
            return 1;
        }

        if (fds[0].revents & POLLIN) {
            if (wl_display_dispatch(display) < 0) {
                fprintf(stderr, "bridge: Wayland connection lost\n");
                return 1;
            }
        }

        if (inotify_fd >= 0 && (fds[1].revents & POLLIN)) {
            char buf[4096];
            while (read(inotify_fd, buf, sizeof(buf)) > 0) {
                // Contents do not matter: any change to /dev/input triggers a
                // rescan, and try_open_device() filters and de-duplicates.
            }
            scan_devices();
        }

        // Walk backwards so drop_device()'s swap-with-last cannot skip an entry.
        for (int i = device_count - 1; i >= 0; i--) {
            for (int j = 2; j < n; j++) {
                if (fds[j].fd == devices[i].fd && (fds[j].revents & (POLLIN | POLLERR | POLLHUP))) {
                    pump_device(i);
                    break;
                }
            }
        }
    }

    return 0;
}
