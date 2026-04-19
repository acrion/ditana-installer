# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of Ditana Installer, see
# https://github.com/acrion/ditana-installer and https://ditana.org/installer.
#
# Ditana Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ditana Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ditana Installer. If not, see <https://www.gnu.org/licenses/>.

use v6.d;
use Settings;
use Logging;

sub create-mimeapps-list() is export {
    Logging.log("Creating MIME applications list...");

    my $s = Settings.instance;
    my $mimeapps-path = $s.get("real-install")
        ?? "/mnt/usr/share/applications/mimeapps.list"
        !! "/tmp/ditana-mimeapps.list";
    $mimeapps-path.IO.parent.mkdir unless $mimeapps-path.IO.parent.d;

    my %mime;

    # Text editor — priority: vscode > fresh > nvim
    my $text-editor = do {
        if $s.get("install-vscode")     { "code.desktop" }
        elsif $s.get("install-fresh")   { "fresh.desktop" }
        else                            { "nvim.desktop" }
    };

    for <text/plain text/x-readme text/x-install text/x-log text/x-changelog
         text/x-authors text/x-makefile text/x-cmake text/x-meson> -> $type {
        %mime{$type} = $text-editor;
    }

    # PDF viewer
    if $s.get("install-xreader") {
        for <application/pdf application/x-pdf> -> $type {
            %mime{$type} = "xreader.desktop";
        }
    }

    # Web browser
    if $s.get("install-librewolf") {
        for <text/html text/xml application/xhtml+xml application/xml
             x-scheme-handler/http x-scheme-handler/https> -> $type {
            %mime{$type} = "librewolf.desktop";
        }
    }

    # Archive manager
    if $s.get("install-engrampa") {
        for <application/x-7z-compressed application/x-7z-compressed-tar
             application/x-ace application/x-alz application/x-ar
             application/x-archive application/x-arj application/x-bzip
             application/x-bzip-compressed-tar application/x-bzip1
             application/x-bzip1-compressed-tar application/x-cabinet
             application/x-cd-image application/x-compress
             application/x-compressed-tar application/x-cpio
             application/x-deb application/x-gtar application/x-gzip
             application/x-gzpostscript application/x-java-archive
             application/x-lha application/x-lhz application/x-lrzip
             application/x-lrzip-compressed-tar application/x-lz4
             application/x-lz4-compressed-tar application/x-lzip
             application/x-lzip-compressed-tar application/x-lzma
             application/x-lzma-compressed-tar application/x-lzop
             application/x-lzop-compressed-tar application/x-rar
             application/x-rar-compressed application/x-rpm
             application/x-rzip application/x-rzip-compressed-tar
             application/x-tar application/x-tarz application/x-tzo
             application/x-xar application/x-xz application/x-xz-compressed-tar
             application/x-zip application/x-zip-compressed
             application/x-zstd-compressed-tar application/x-zoo
             application/zip application/gzip application/bzip2> -> $type {
            %mime{$type} = "engrampa.desktop";
        }
    }

    # File manager
    if $s.get("install-thunar") {
        for <inode/directory> -> $type {
            %mime{$type} = "thunar.desktop";
        }
    } elsif $s.get("install-yazi") {
        for <inode/directory> -> $type {
            %mime{$type} = "yazi.desktop";
        }
    }

    # Image viewer
    if $s.get("install-ristretto") {
        for <image/bmp image/gif image/jpeg image/jpg image/pjpeg
             image/png image/svg+xml image/svg+xml-compressed
             image/tiff image/vnd.microsoft.icon image/x-bmp
             image/x-gray image/x-icb image/x-ico image/x-icon
             image/x-pcx image/x-png image/x-portable-anymap
             image/x-portable-bitmap image/x-portable-graymap
             image/x-portable-pixmap image/x-xbitmap image/x-xpixmap> -> $type {
            %mime{$type} = "org.xfce.ristretto.desktop";
        }
    }

    # Media player
    if $s.get("install-vlc") {
        # Audio
        for <audio/3gpp audio/3gpp2 audio/aac audio/ac3 audio/amr
             audio/amr-wb audio/basic audio/dv audio/eac3 audio/flac
             audio/m4a audio/midi audio/mp1 audio/mp2 audio/mp3
             audio/mp4 audio/mpeg audio/mpegurl audio/mpg audio/ogg
             audio/opus audio/scpls audio/vnd.dolby.dd-raw audio/vnd.dts
             audio/vnd.dts.hd audio/vnd.rn-realaudio audio/vorbis
             audio/wav audio/webm audio/x-aac audio/x-aiff audio/x-ape
             audio/x-flac audio/x-m4a audio/x-matroska audio/x-mp1
             audio/x-mp2 audio/x-mp3 audio/x-mpeg audio/x-mpegurl
             audio/x-ms-asf audio/x-ms-asx audio/x-ms-wax audio/x-ms-wma
             audio/x-musepack audio/x-pn-aiff audio/x-pn-au
             audio/x-pn-realaudio audio/x-pn-realaudio-plugin
             audio/x-pn-wav audio/x-pn-windows-acm audio/x-real-audio
             audio/x-realaudio audio/x-shorten audio/x-speex
             audio/x-tta audio/x-vorbis audio/x-vorbis+ogg
             audio/x-wav audio/x-wavpack audio/x-adpcm audio/x-gsm
             audio/x-it audio/x-mod audio/x-s3m audio/x-xm
             audio/x-scpls audio/vnd.dolby.heaac.1 audio/vnd.dolby.heaac.2
             audio/vnd.dolby.mlp> -> $type {
            %mime{$type} = "vlc.desktop";
        }

        # Video
        for <video/3gp video/3gpp video/3gpp2 video/avi video/dv
             video/fli video/flv video/mp2t video/mp4 video/mp4v-es
             video/mpeg video/mpeg-system video/msvideo video/ogg
             video/quicktime video/vnd.mpegurl video/vnd.rn-realvideo
             video/webm video/x-avi video/x-flc video/x-fli video/x-flv
             video/x-m4v video/x-matroska video/x-mpeg video/x-mpeg-system
             video/x-mpeg2 video/x-ms-asf video/x-ms-asf-plugin
             video/x-ms-asx video/x-ms-wm video/x-ms-wmv video/x-ms-wmx
             video/x-ms-wvx video/x-msvideo video/x-ogm video/x-ogm+ogg
             video/x-theora video/x-theora+ogg video/x-anim video/x-nsv
             video/divx video/vnd.divx> -> $type {
            %mime{$type} = "vlc.desktop";
        }

        # VLC-specific application types and scheme handlers
        for <application/ogg application/x-ogg application/mxf
             application/sdp application/vnd.ms-asf application/vnd.ms-wpl
             application/vnd.rn-realmedia application/vnd.rn-realmedia-vbr
             application/ram application/xspf+xml application/vnd.apple.mpegurl
             application/x-cd-image application/x-extension-m4a
             application/x-extension-mp4 application/x-matroska
             application/x-quicktime-media-link application/x-quicktimeplayer
             application/x-shockwave-flash application/x-flash-video
             application/mpeg4-iod application/mpeg4-muxcodetable
             x-scheme-handler/mms x-scheme-handler/mmsh x-scheme-handler/rtsp
             x-scheme-handler/rtp x-scheme-handler/rtmp x-scheme-handler/icy
             x-scheme-handler/icyx x-content/video-vcd x-content/video-svcd
             x-content/video-dvd x-content/audio-cdda x-content/audio-player
             text/google-video-pointer text/x-google-video-pointer
             image/vnd.rn-realpix misc/ultravox> -> $type {
            %mime{$type} = "vlc.desktop";
        }
    }

    # Terminal emulator scheme handler (consumed by Nautilus, some GTK file managers,
    # and certain "Open Terminal Here" actions). Priority matches the KDL block order
    # and the last-writer-wins behaviour of the /etc/environment TERMINAL entry:
    # install-foot overrides install-kitty when both are selected.
    my $terminal-desktop;
    $terminal-desktop = "kitty.desktop" if $s.get("install-kitty");
    $terminal-desktop = "foot.desktop"  if $s.get("install-foot");
    %mime{"x-scheme-handler/terminal"} = $terminal-desktop if $terminal-desktop;

    # Write
    my $content = "[Default Applications]\n";
    for %mime.sort(*.key) -> $pair {
        $content ~= "{$pair.key}={$pair.value}\n";
    }

    $mimeapps-path.IO.spurt($content);
    Logging.log("Created MIME applications list at $mimeapps-path");
}
