{ ... }:
{
  flake.homeModules.taskwarrior =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.taskwarrior3 ];

      xdg.configFile."task/taskrc".text = ''
        # Taskwarrior 3 configuration
        confirmation=off
        color=on
        rule.color.checked=on
        rule.color.label=on
        urgency.next.coefficient=0

        # Sync settings (incl. encryption secret) rendered by sops —
        # declared system-side in isaacHomeManager
        include /run/secrets/rendered/task-sync.rc

        # Dates
        dateformat=Y-M-D
        dateformat.report=
        due=7

        # Display
        default.command=next
        report.next.columns=id,start.age,entry.age,priority,project,tags,recur,due.relative,description.count
        report.next.labels=ID,Active,Age,P,Project,Tags,Recur,Due,Description
        report.next.sort=urgency-,due+
      '';
    };
}
