{ config, pkgs, lib, minimal-emacs, ... }:

let
  # ── Detect user from environment ────────────────────────────────────
  # home-manager switch passes --impure so builtins.getEnv works.
  # Fallbacks are used when evaluating in pure mode (e.g. nix flake check).
  envUser = builtins.getEnv "USER";
  envHome = builtins.getEnv "HOME";

  username = if envUser != "" then envUser
             else "jay";

  homeDirectory = if envHome != "" then envHome
                  else if pkgs.stdenv.isDarwin then "/Users/${username}"
                  else "/home/${username}";

  # ── Custom packages not in nixpkgs ──────────────────────────────────

  opencode = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "1.2.24";

    src = let
      platform = {
        "x86_64-linux"    = { suffix = "linux-x64";   ext = "tar.gz"; hash = "sha256-IGRO9rhZdfC0nD6hMcjUnN7oVEGbO4z7JEduAXh6hx4="; };
        "aarch64-linux"   = { suffix = "linux-arm64";  ext = "tar.gz"; hash = "sha256-WFB7mMKQL9gZudJjlZTuxPNuVwjxFLoCixw+h3u15H0="; };
        "aarch64-darwin"  = { suffix = "darwin-arm64"; ext = "zip";    hash = "sha256-hYRnFVlDwQMIFQR8vaL9UHTRupMJoA5d1FhaGbPEiW4="; };
      }.${pkgs.stdenv.hostPlatform.system} or (throw "opencode: unsupported system ${pkgs.stdenv.hostPlatform.system}");
    in pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platform.suffix}.${platform.ext}";
      hash = platform.hash;
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.makeWrapper ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.unzip ];

    dontStrip = true;
    dontPatchELF = true;
    dontAutoPatchelf = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 opencode $out/bin/.opencode-unwrapped
      runHook postInstall
    '';

    postFixup = lib.optionalString pkgs.stdenv.isLinux ''
      makeWrapper $out/bin/.opencode-unwrapped $out/bin/opencode \
        --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}"
    '' + lib.optionalString pkgs.stdenv.isDarwin ''
      mv $out/bin/.opencode-unwrapped $out/bin/opencode
    '';

    meta = {
      description = "AI coding assistant for the terminal";
      homepage = "https://opencode.ai";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
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

in {

  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # ── Packages ────────────────────────────────────────────────────────

  home.packages = with pkgs; [
    # Editor
    emacs-nox

    # Shell & terminal
    zellij
    starship
    eza

    # Languages
    go
    gopls
    python3
    racket
    typst
    tinymist
    templ

    # Python tools
    uv
    ruff

    # Utilities
    ripgrep
    fzf
    zoxide
    git-lfs

    # Fonts
    fira-code

    # Build tools
    gcc

    # Custom packages
    opencode
  ] ++ lib.optionals stdenv.isLinux [
    earlyoom
    inotify-tools
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
  ];

  # ── Fish shell ──────────────────────────────────────────────────────
  # home-manager generates its own config.fish (with session vars, etc.),
  # so we source our custom config from interactiveShellInit instead of
  # symlinking config.fish directly.

  programs.fish = {
    enable = true;
    interactiveShellInit = builtins.readFile ./config/fish/config.fish;
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
  # unmanaged so Fisher can write to it after plugin installs)
  xdg.configFile = {
    "fish/functions/fisher.fish".source = ./config/fish/functions/fisher.fish;
    "fish/functions/zlast.fish".source = ./config/fish/functions/zlast.fish;
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
      include.path = "~/.config/git/local";
    };

    includes = [
      {
        condition = "gitdir:~/Code/engineering-resume/";
        path = "~/.config/git/codeberg";
      }
    ];
  };

  # Codeberg conditional config (raw file, referenced by includes above)
  xdg.configFile."git/codeberg".source = ./config/git/codeberg;

  # ── Emacs ───────────────────────────────────────────────────────────
  # Emacs config uses Elpaca for package management, so we just symlink
  # the config files. minimal-emacs.d is a flake input.

  xdg.configFile."emacs/early-init.el".source = "${minimal-emacs}/early-init.el";
  xdg.configFile."emacs/init.el".source = "${minimal-emacs}/init.el";
  xdg.configFile."emacs/pre-early-init.el".source = ./config/emacs/pre-early-init.el;
  xdg.configFile."emacs/pre-init.el".source = ./config/emacs/pre-init.el;
  xdg.configFile."emacs/post-init.el".source = ./config/emacs/post-init.el;
  xdg.configFile."emacs/elpaca-lock.el".source = ./config/emacs/elpaca-lock.el;

  # ── Zellij ──────────────────────────────────────────────────────────

  xdg.configFile."zellij/config.kdl".source = ./config/zellij/config.kdl;

  xdg.configFile."zellij/layouts" = {
    source = ./config/zellij/layouts;
    recursive = true;
  };

  xdg.configFile."zellij/themes" = {
    source = ./config/zellij/themes;
    recursive = true;
  };

  # Zellij plugins (zjstatus from derivation, emacs-session from local wasm)
  xdg.configFile."zellij/plugins/zjstatus.wasm".source =
    "${zjstatus}/share/zellij/plugins/zjstatus.wasm";
  xdg.configFile."zellij/plugins/zellij-emacs-session.wasm".source =
    ./zellij-emacs-session/zellij-emacs-session.wasm;

  # ── User scripts (~/bin/) ───────────────────────────────────────────

  home.file."bin/watch-theme-zellij.sh" = {
    source = ./config/bin/watch-theme-zellij.sh;
    executable = true;
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
          "PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.gnused pkgs.inotify-tools ]}:%h/bin"
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
      ProgramArguments = [ "${pkgs.emacs-nox}/bin/emacs" "--fg-daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # ── Terminfo (activation script) ────────────────────────────────────

  home.activation.compileTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "${./config/terminfo/xterm-ghostty.ti}" ]; then
      run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" "${./config/terminfo/xterm-ghostty.ti}"
    fi
  '';

}
