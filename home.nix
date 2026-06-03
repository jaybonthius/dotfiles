{
  config,
  pkgs,
  lib,
  minimal-emacs,
  ...
}:

let
  # ── Detect user from environment ────────────────────────────────────
  # home-manager switch passes --impure so builtins.getEnv works.
  # Fallbacks are used when evaluating in pure mode (e.g. nix flake check).
  envUser = builtins.getEnv "USER";
  envHome = builtins.getEnv "HOME";

  username = if envUser != "" then envUser else "jay";

  homeDirectory =
    if envHome != "" then
      envHome
    else if pkgs.stdenv.isDarwin then
      "/Users/${username}"
    else
      "/home/${username}";

  # ── Custom packages not in nixpkgs ──────────────────────────────────

  zjstatus = pkgs.stdenv.mkDerivation rec {
    pname = "zjstatus";
    version = "0.22.0";

    src = pkgs.fetchurl {
      url = "https://github.com/dj95/zjstatus/releases/download/v${version}/zjstatus.wasm";
      hash = "sha256-TeQm0gscv4YScuknrutbSdksF/Diu50XP4W/fwFU3VM=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm644 $src $out/share/zellij/plugins/zjstatus.wasm
      runHook postInstall
    '';

    meta = {
      description = "Configurable statusbar plugin for zellij";
      homepage = "https://github.com/dj95/zjstatus";
      license = lib.licenses.mit;
    };
  };

  zellij-smart-switch = ./config/zellij/plugins/zellij-smart-switch.wasm;

in
{

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # ── Packages ────────────────────────────────────────────────────────

  home.packages =
    with pkgs;
    [
      # Shell & terminal
      tmux
      zellij
      starship
      eza

      # Languages
      nodejs
      pnpm
      python3
      python3Packages.grip
      typst
      tinymist
      templ
      nixd
      nixfmt-rfc-style

      # Utilities
      ripgrep
      cmark
      fzf
      jq
      zoxide
      git-lfs
      difftastic
      postgresql
      netcat-openbsd
      forgejo-cli

      # Fonts
      fira-code

      # Build tools
      gcc

      # Custom packages
      opener
    ]
    ++ lib.optionals (!(stdenv.isLinux && stdenv.hostPlatform.isx86_64)) [
      go
      gopls
    ]
    ++ lib.optionals (stdenv.isLinux && stdenv.hostPlatform.isAarch64) [
      uv
    ]
    ++ lib.optionals stdenv.isLinux [
      emacs-nox
      earlyoom
      inotify-tools
    ]
    ++ lib.optionals stdenv.isDarwin [
      fswatch
    ];

  # ── Environment variables ───────────────────────────────────────────

  home.sessionVariables = {
    COLORTERM = "truecolor";
    GOPATH = "$HOME/go";
    GOBIN = "$HOME/go/bin";
    PNPM_HOME = "$HOME/.local/share/pnpm";
  };

  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/go/bin"
    "$HOME/.local/share/pnpm"
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    "/Applications/Emacs.app/Contents/MacOS/bin"
  ];

  # ── Fish shell ──────────────────────────────────────────────────────
  # home-manager generates its own config.fish (with session vars, etc.),
  # so we source our custom config from interactiveShellInit instead of
  # symlinking config.fish directly.

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile ./config/fish/config.fish;
  };

  # Launch fish from bash since we can't chsh without root.
  # Only exec when bash is the login shell and we're interactive,
  # so scripts/non-interactive sessions stay in bash.
  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -z "$__FISH_LAUNCHED" ] && command -v fish &>/dev/null; then
        export __FISH_LAUNCHED=1
        exec fish -l
      fi
    '';
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = false; # we call `starship init fish | source` in config.fish
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = false; # we call `zoxide init` in config.fish
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = false; # we use PatrickF1/fzf.fish plugin instead
  };

  # Symlink fish support files (functions only — fish_plugins is left
  # unmanaged so Fisher can write to it after plugin installs).
  # Out-of-store symlinks so edits take effect without `home-manager switch`.
  xdg.configFile = {
    "fish/functions/fisher.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/fisher.fish";
      force = true;
    };
    "fish/functions/zlast.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/zlast.fish";
      force = true;
    };
    "fish/functions/ws.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/ws.fish";
      force = true;
    };
    "fish/functions/athenaq.fish" = {
      source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/fish/functions/athenaq.fish";
      force = true;
    };
  };

  # Seed fish_plugins on first run only (Fisher owns it after that)
  home.activation.seedFishPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.config/fish/fish_plugins" ]; then
      run mkdir -p "$HOME/.config/fish"
      run cp "${./config/fish/fish_plugins}" "$HOME/.config/fish/fish_plugins"
      run chmod 644 "$HOME/.config/fish/fish_plugins"
    fi
  '';

  # ── Git ─────────────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    lfs.enable = true;

    settings = {
      user = {
        name = "Jay Bonthius";
        email = "jaybonthius@gmail.com";
      };
      init.defaultBranch = "main";
      alias = {
        dft = "-c diff.external=difft diff";
        ds = "-c diff.external=difft show --ext-diff";
        dl = "-c diff.external=difft log -p --ext-diff";
      };
    };

    includes = [
      {
        path = "~/.config/git/local";
      }
      {
        condition = "gitdir:~/Code/engineering-resume/";
        path = "~/.config/git/codeberg";
      }
    ];
  };

  # Codeberg conditional config (raw file, referenced by includes above)
  xdg.configFile."git/codeberg" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/git/codeberg";
    force = true;
  };

  # ── Emacs ───────────────────────────────────────────────────────────
  # Emacs config uses Elpaca for package management, so we just symlink
  # the config files. minimal-emacs.d is a flake input.
  #
  # Local files use mkOutOfStoreSymlink so edits take effect on Emacs
  # restart without needing `home-manager switch`.

  xdg.configFile."emacs/early-init.el" = {
    source = "${minimal-emacs}/early-init.el";
    force = true;
  };
  xdg.configFile."emacs/init.el" = {
    source = "${minimal-emacs}/init.el";
    force = true;
  };
  xdg.configFile."emacs/pre-early-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/pre-early-init.el";
    force = true;
  };
  xdg.configFile."emacs/pre-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/pre-init.el";
    force = true;
  };
  xdg.configFile."emacs/post-init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/emacs/post-init.el";
    force = true;
  };
  # ── Claude Code ─────────────────────────────────────────────────────
  # Base config (personal/non-work settings). Merged with
  # settings.local.json (work plugins, gitignored) at activation time
  # to produce the final ~/.claude/settings.json.

  home.file.".claude/settings.base.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/claude/settings.base.json";
    force = true;
  };

  # ── Pi Coding Agent ──────────────────────────────────────────────────
  # Base config (personal settings + packages). Merged with
  # settings.local.json (machine-specific overrides, gitignored) at
  # activation time to produce the final ~/.pi/agent/settings.json.

  home.file.".pi/agent/settings.base.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/settings.base.json";
    force = true;
  };

  home.file.".pi/agent/agents" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/agents";
    force = true;
  };

  home.file.".pi/agent/extensions" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/extensions";
    force = true;
  };

  # Global Pi skills managed from dotfiles.
  home.file.".agents/skills/subagent-orchestrator" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/pi/skills/subagent-orchestrator";
    force = true;
  };

  # ── Tmux ────────────────────────────────────────────────────────────

  xdg.configFile."tmux/tmux.conf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/tmux/tmux.conf";
    force = true;
  };

  xdg.configFile."tmux/themes" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/tmux/themes";
    force = true;
  };

  # ── Zellij ──────────────────────────────────────────────────────────

  xdg.configFile."zellij/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/config.kdl";
    force = true;
  };

  xdg.configFile."zellij/layouts" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/layouts";
    force = true;
  };

  # Zellij plugins (from derivations)
  xdg.configFile."zellij/plugins/zjstatus.wasm" = {
    source = "${zjstatus}/share/zellij/plugins/zjstatus.wasm";
    force = true;
  };

  xdg.configFile."zellij/plugins/zellij-smart-switch.wasm" = {
    source = zellij-smart-switch;
    force = true;
  };

  # ── User scripts (~/bin/) ───────────────────────────────────────────

  home.file."bin/opener-open" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/bin/opener-open";
    force = true;
  };

  home.file."bin/emacs-open-context" = {
    source = ./config/bin/emacs-open-context;
    executable = true;
    force = true;
  };

  home.file."bin/zellij-session-open" = {
    source = ./config/bin/zellij-session-open;
    executable = true;
    force = true;
  };

  home.file."bin/zellij-sessionizer" = {
    source = ./config/bin/zellij-sessionizer;
    executable = true;
    force = true;
  };

  home.file."bin/theme-state-to-gsettings" = {
    source = ./config/bin/theme-state-to-gsettings;
    executable = true;
    force = true;
  };

  home.file."bin/git-sync-main-master" = {
    source = ./config/bin/git-sync-main-master;
    executable = true;
    force = true;
  };

  # ── Systemd user services (Linux only) ──────────────────────────────

  systemd.user.services = lib.mkIf pkgs.stdenv.isLinux {

    emacs-daemon = {
      Unit = {
        Description = "Emacs daemon";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.emacs-nox}/bin/emacs --fg-daemon";
        Restart = "on-failure";
        RestartSec = "3s";
        Environment = [
          "PATH=%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:%h/bin:%h/go/bin:/usr/local/bin:/usr/bin:/bin"
          "SSH_AUTH_SOCK=%h/.ssh/ssh_auth_sock"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    theme-state-to-gsettings = {
      Unit = {
        Description = "Sync ~/.local/state/theme to GNOME gsettings";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "%h/bin/theme-state-to-gsettings";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };

  systemd.user.paths = lib.mkIf pkgs.stdenv.isLinux {
    theme-state-to-gsettings = {
      Unit = {
        Description = "Watch ~/.local/state/theme and sync GNOME appearance";
      };
      Path = {
        PathChanged = [
          "%h/.local/state/theme"
          "%h/.local/state"
        ];
        Unit = "theme-state-to-gsettings.service";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };

  # ── Launchd agents (macOS only) ─────────────────────────────────────

  launchd.agents.emacs-daemon = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "/Applications/Emacs.app/Contents/MacOS/Emacs"
        "--fg-daemon"
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # ── Terminfo (activation script) ────────────────────────────────────

  home.activation.compileTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "${./config/terminfo/xterm-ghostty.ti}" ]; then
      run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" "${./config/terminfo/xterm-ghostty.ti}"
    fi
    if [ -f "${./config/terminfo/tmux-direct.ti}" ]; then
      run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" "${./config/terminfo/tmux-direct.ti}"
    fi
  '';

  # ── Claude Code config merge (activation scripts) ──────────────────
  # settings.base.json   — Nix-managed personal plugins (home.file above)
  # settings.local.json  — work plugins / Cox-specific (gitignored)
  # settings.json        — deep-merged result, rewritten every activation

  # Seed settings.local.json once from the existing settings.json's
  # work-specific keys (genai-enablement plugins + extraKnownMarketplaces).
  # After seeding, the file is left alone so the user can edit it freely.
  home.activation.seedClaudeLocal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    local="$HOME/.claude/settings.local.json"
    current="$HOME/.claude/settings.json"
    if [ ! -f "$local" ] && [ -f "$current" ]; then
      run mkdir -p "$HOME/.claude"
      # Extract work-specific plugins and marketplaces
      run ${pkgs.jq}/bin/jq '{
        enabledPlugins: (.enabledPlugins // {} | with_entries(select(.key | endswith("@genai-enablement")))),
        extraKnownMarketplaces: (.extraKnownMarketplaces // {})
      }' "$current" > "$local"
    fi
  '';

  # Install pnpm global packages (deep merge, OpenSpec, pi-coding-agent, skills).
  # PATH must include nodejs/bin so postinstall scripts can find `node`,
  # and PNPM_HOME must be on PATH for pnpm to accept global installs.
  home.activation.installPnpmGlobals = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    run mkdir -p "$PNPM_HOME"
    PATH="${pkgs.nodejs}/bin:$PNPM_HOME:$PATH" \
      run ${pkgs.pnpm}/bin/pnpm add -g deepmerge @fission-ai/openspec@latest @earendil-works/pi-coding-agent skills
  '';

  # Install Caveman skills globally for Claude Code and Pi.
  home.activation.installCavemanSkill =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "installPnpmGlobals"
      ]
      ''
        export PNPM_HOME="$HOME/.local/share/pnpm"
        PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PNPM_HOME:$PATH"

        run ${pkgs.nodejs}/bin/npx -y skills add JuliusBrussee/caveman -g -a claude-code pi -y
      '';

  # ── Pi Coding Agent config merge (activation scripts) ───────────────
  # settings.base.json  — Nix-managed settings + packages (home.file above)
  # settings.local.json — machine-specific overrides (gitignored)
  # settings.json       — deep-merged result, rewritten every activation

  # Seed settings.local.json once from the existing settings.json's
  # non-base keys. After seeding, the file is left alone so the user
  # can edit it freely.
  home.activation.seedPiLocal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    local="$HOME/.pi/agent/settings.local.json"
    current="$HOME/.pi/agent/settings.json"
    if [ ! -f "$local" ] && [ -f "$current" ]; then
      run mkdir -p "$HOME/.pi/agent"
      # Extract keys that are NOT in the base config
      run ${pkgs.jq}/bin/jq '{
        lastChangelogVersion: .lastChangelogVersion
      } | with_entries(select(.value != null))' "$current" > "$local"
    fi
  '';

  # Merge base + local into settings.json on every activation.
  home.activation.mergePiConfig =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedPiLocal"
        "installPnpmGlobals"
      ]
      ''
        base="$HOME/.pi/agent/settings.base.json"
        local="$HOME/.pi/agent/settings.local.json"
        target="$HOME/.pi/agent/settings.json"

        run mkdir -p "$HOME/.pi/agent"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.local/share/pnpm/global/5/node_modules/deepmerge');
            const fs = require('fs');
            const a = JSON.parse(fs.readFileSync('$base'));
            const b = JSON.parse(fs.readFileSync('$local'));
            console.log(JSON.stringify(m(a, b), null, 2));
          " > "$target"
        else
          run cp "$base" "$target"
        fi
      '';

  # Merge base + local into settings.json on every activation.
  # Uses deepmerge-cli for proper recursive merge with array union.
  home.activation.mergeClaudeConfig =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedClaudeLocal"
        "installPnpmGlobals"
      ]
      ''
        base="$HOME/.claude/settings.base.json"
        local="$HOME/.claude/settings.local.json"
        target="$HOME/.claude/settings.json"

        run mkdir -p "$HOME/.claude"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.local/share/pnpm/global/5/node_modules/deepmerge');
            const fs = require('fs');
            const a = JSON.parse(fs.readFileSync('$base'));
            const b = JSON.parse(fs.readFileSync('$local'));
            console.log(JSON.stringify(m(a, b), null, 2));
          " > "$target"
        else
          run cp "$base" "$target"
        fi
      '';

}
