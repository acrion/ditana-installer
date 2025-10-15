use path
use epm
use str

fn get-package-installer {
  var installers = [pakku aurman trizen pikaur paru yay pacman]
  
  # Return the first available installer
  each {|installer|
    if (has-external $installer) {
      put $installer
      return
    }
  } $installers
  
  fail "This code (see" (src)[name]") is meant to be used on Arch based Linux systems."
}

var installer = (external (get-package-installer))

# Check for OpenMPI
if ?($installer -Qi openmpi 2>/dev/null >/dev/null) {
  set-env OPENMPI_DIR /usr
}

# Check for Intel oneAPI MKL
if ?($installer -Q intel-oneapi-mkl 2>/dev/null >/dev/null) {
  var mkl-header = ($installer -Ql intel-oneapi-mkl | grep 'mkl.h$' | awk '{print $2}' | head -n 1)
  if (not-eq $mkl-header "") {
    var mkl-dir = (dirname $mkl-header)
    set-env MKL_INCLUDE_PATH $mkl-dir
    set-env CXXFLAGS "-I"$mkl-dir" "$E:CXXFLAGS
  }
}

# Check for archlinux-java
try {
  var java-version = (str:trim-space (archlinux-java get))
  set-env JAVA_HOME /usr/lib/jvm/$java-version
} catch e {
  # Silently ignore if archlinux-java is not configured or fails
}


# Set JAVA_COMPILER if javac exists
if (and (has-env JAVA_HOME) (path:is-regular $E:JAVA_HOME/bin/javac)) {
  set-env JAVA_COMPILER $E:JAVA_HOME/bin/javac
}

# Add directories to PATH if they exist
var dirs-to-prepend-to-path = [
  ~/.local/bin
  ~/bin
  ~/go/bin
  /usr/share/perl6/site/bin
  ~/.raku/bin
  /usr/local/cuda/bin
]

each {|dir|
  if (path:is-dir $dir) {
    set paths = [$dir $@paths]
  }
} $dirs-to-prepend-to-path

# Aliases for common commands
fn ll {|@args| e:exa --long --icons --classify --hyperlink --group-directories-first --git $@args }

fn get-orphaned {
    $installer --query --unrequired --deps --quiet
}

fn rm-orphaned {
  var orphans = (get-orphaned)
  
  if (not-eq (count $orphans) 0) {
    echo "Removing orphaned packages:" $@orphans
    $installer --remove --nosave --recursive $@orphans
  } else {
    echo "No orphaned packages to remove."
  }
}

fn monitor-dir { |@args|
  if ?($installer -Q inotify-tools 2>/dev/null >/dev/null) {
    e:inotifywait -m -r -e modify -e create -e delete $@args
  } else {
    fail "Run '"$installer" -S inotify-tools' to use this function"
  }
}

fn addpkg {|@args| $installer -Syu $@args }

fn rmpkg {|@args| $installer -Rsu $@args }

# Execute system info script if it exists
if (has-external print-system-infos) {
  print-system-infos
} elif (has-external fastfetch) {
  fastfetch
} elif (has-external neofetch) {
  neofetch
}

try {
  set-env CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
  eval (carapace _carapace|slurp)
} catch e {
  # Silently ignore if carapace is not installed
}

if (epm:is-installed github.com/zzamboni/elvish-modules) {
  use github.com/zzamboni/elvish-modules/terminal-title
}

if (epm:is-installed github.com/zzamboni/elvish-themes) {
  use github.com/zzamboni/elvish-themes/chain
  set chain:prompt-pwd-dir-length = 0
  set chain:prompt-segments = [ su git-branch git-combined arrow ]
  set chain:rprompt-segments = [ dir ]
  chain:init
}
