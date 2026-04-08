# Add system-wide optional directories to PATH

for _dir in /usr/share/perl6/site/bin /usr/local/cuda/bin; do
    if [[ -d "$_dir" ]]; then
        export PATH="$_dir:$PATH"
    fi
done
unset _dir
