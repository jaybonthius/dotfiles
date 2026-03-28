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

  opencode = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "1.3.3";

    src =
      let
        platform =
          {
            "x86_64-linux" = {
              suffix = "linux-x64";
              ext = "tar.gz";
              hash = "sha256-YJzxhLraGLyiDg2AWvB90Aj4kCNsvVK0FTRt4jhk3TI=";
            };
            "aarch64-linux" = {
              suffix = "linux-arm64";
              ext = "tar.gz";
              hash = "sha256-ocVx/JBB4fHbF0rF7sT/B48curk5J9he2pgvG8k5NKQ=";
            };
            "aarch64-darwin" = {
              suffix = "darwin-arm64";
              ext = "zip";
              hash = "sha256-UnJRRxO7lYjS6fOglADYMGwlas2CsG6e6ScEcCnqtcA=";
            };
          }
          .${pkgs.stdenv.hostPlatform.system}
            or (throw "opencode: unsupported system ${pkgs.stdenv.hostPlatform.system}");
      in
      pkgs.fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platform.suffix}.${platform.ext}";
        hash = platform.hash;
      };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.makeWrapper ] ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.unzip ];

    dontStrip = true;
    dontPatchELF = true;
    dontAutoPatchelf = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 opencode $out/bin/.opencode-unwrapped
      runHook postInstall
    '';

    postFixup =
      lib.optionalString pkgs.stdenv.isLinux ''
        makeWrapper $out/bin/.opencode-unwrapped $out/bin/opencode \
          --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}"
      ''
      + lib.optionalString pkgs.stdenv.isDarwin ''
        mv $out/bin/.opencode-unwrapped $out/bin/opencode
      '';

    meta = {
      description = "AI coding assistant for the terminal";
      homepage = "https://opencode.ai";
      license = lib.licenses.mit;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  };

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
      zellij
      starship
      eza

      # Languages
      go
      gopls
      nodejs
      python3
      racket
      typst
      tinymist
      templ
      nixd
      nixfmt-rfc-style

      # Python tools
      uv
      ruff

      # Utilities
      ripgrep
      fzf
      jq
      zoxide
      git-lfs
      postgresql
      netcat-openbsd
      forgejo-cli

      # Fonts
      fira-code

      # Build tools
      gcc

      # Custom packages
      opencode
      opener
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
  };

  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/go/bin"
    "$HOME/.npm-global/bin"
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
  # ── OpenCode ────────────────────────────────────────────────────────
  # TUI keybind overrides for running OpenCode inside Emacs eat.
  # Leader changed from ctrl+x (intercepted by eat) to ctrl+s.

  xdg.configFile."opencode/tui.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/opencode/tui.json";
    force = true;
  };

  # Base config (personal/non-secret settings). Merged with
  # config.local.json (work secrets, gitignored) at activation time
  # to produce the final config.json.
  xdg.configFile."opencode/config.base.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/opencode/config.base.json";
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

  # ── Zellij ──────────────────────────────────────────────────────────

  xdg.configFile."zellij/config.kdl" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/config.kdl";
    force = true;
  };

  xdg.configFile."zellij/layouts" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/layouts";
    force = true;
  };

  xdg.configFile."zellij/themes" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/zellij/themes";
    force = true;
  };

  # Zellij plugins (zjstatus from derivation, emacs-session from local wasm)
  xdg.configFile."zellij/plugins/zjstatus.wasm" = {
    source = "${zjstatus}/share/zellij/plugins/zjstatus.wasm";
    force = true;
  };
  xdg.configFile."zellij/plugins/zellij-emacs-session.wasm" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/zellij-emacs-session/zellij-emacs-session.wasm";
    force = true;
  };

  # ── User scripts (~/bin/) ───────────────────────────────────────────

  home.file."bin/watch-theme-zellij.sh" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/bin/watch-theme-zellij.sh";
    force = true;
  };

  home.file."bin/opener-open" = {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dotfiles/config/bin/opener-open";
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

    theme-watcher = {
      Unit = {
        Description = "Watch theme state file and update Zellij theme";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "%h/bin/watch-theme-zellij.sh";
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          "PATH=${
            lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.gnused
              pkgs.inotify-tools
            ]
          }:%h/bin"
        ];
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

  launchd.agents.theme-watcher = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${homeDirectory}/bin/watch-theme-zellij.sh"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        PATH = lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnused
          pkgs.fswatch
        ];
        HOME = homeDirectory;
      };
    };
  };

  # ── Terminfo (activation script) ────────────────────────────────────

  home.activation.compileTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "${./config/terminfo/xterm-ghostty.ti}" ]; then
      run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" "${./config/terminfo/xterm-ghostty.ti}"
    fi
  '';

  # ── OpenCode config merge (activation scripts) ─────────────────────
  # config.base.json  — Nix-managed personal settings (xdg.configFile above)
  # config.local.json — machine-specific / work secrets (gitignored)
  # config.json       — deep-merged result, rewritten every activation

  # Seed config.local.json once from the existing config.json's non-base
  # keys (e.g. the cai-mcp MCP block). After seeding, the file is left
  # alone so the user can edit it freely.
  home.activation.seedOpenCodeLocal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    local="$HOME/.config/opencode/config.local.json"
    current="$HOME/.config/opencode/config.json"
    if [ ! -f "$local" ] && [ -f "$current" ]; then
      run mkdir -p "$HOME/.config/opencode"
      # Extract only the mcp keys that are NOT in the base config
      run ${pkgs.jq}/bin/jq '{mcp: (.mcp // {} | with_entries(select(.key != "context7")))}' \
        "$current" > "$local"
    fi
  '';

  # Merge base + local into config.json on every activation.
  # Uses deepmerge-cli for proper recursive merge with array union.
  home.activation.mergeOpenCodeConfig =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedOpenCodeLocal"
        "installNpmGlobals"
      ]
      ''
        base="$HOME/.config/opencode/config.base.json"
        local="$HOME/.config/opencode/config.local.json"
        target="$HOME/.config/opencode/config.json"

        run mkdir -p "$HOME/.config/opencode"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.npm-global/lib/node_modules/deepmerge');
            const fs = require('fs');
            const a = JSON.parse(fs.readFileSync('$base'));
            const b = JSON.parse(fs.readFileSync('$local'));
            console.log(JSON.stringify(m(a, b), null, 2));
          " > "$target"
        else
          run cp "$base" "$target"
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

  # Install npm global packages for JSON deep merge and OpenSpec.
  # PATH must include nodejs/bin so postinstall scripts can find `node`.
  home.activation.installNpmGlobals = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.npm-global"
    PATH="${pkgs.nodejs}/bin:$PATH" \
      run ${pkgs.nodejs}/bin/npm install -g --prefix "$HOME/.npm-global" deepmerge @fission-ai/openspec@latest
  '';

  # Merge base + local into settings.json on every activation.
  # Uses deepmerge-cli for proper recursive merge with array union.
  home.activation.mergeClaudeConfig =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "seedClaudeLocal"
        "installNpmGlobals"
      ]
      ''
        base="$HOME/.claude/settings.base.json"
        local="$HOME/.claude/settings.local.json"
        target="$HOME/.claude/settings.json"

        run mkdir -p "$HOME/.claude"
        if [ -f "$local" ]; then
          run ${pkgs.nodejs}/bin/node -e "
            const m = require('$HOME/.npm-global/lib/node_modules/deepmerge');
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
