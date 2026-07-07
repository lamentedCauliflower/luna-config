{ inputs, ... }:
{
  flake.nixosModules.nvim =
    { ... }:
    {
      imports = [ inputs.nvf.nixosModules.default ];

      environment.variables.EDITOR = "nvim";

      programs.nvf = {
        enable = true;
        settings = {
          vim.viAlias = false;
          vim.vimAlias = true;
          vim.lsp = {
            enable = true;
          };

          vim.languages = {
            enableTreesitter = true;
            nix.enable = true;
            rust.enable = true;
            yaml.enable = true;
          };

          vim.autocomplete.nvim-cmp.enable = true;
          vim.assistant.copilot = {
            enable = true;
            cmp.enable = true;
          };
          vim.telescope.enable = true;

          vim.statusline.lualine.enable = true;

          vim.options = {
            tabstop = 2;
            shiftwidth = 2;
            expandtab = true;
          };
        };
      };

    };

}
