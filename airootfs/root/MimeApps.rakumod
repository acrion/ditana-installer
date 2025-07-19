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
    
    my $mimeapps-path = Settings.instance.get("real-install") ?? "/mnt/usr/share/applications/mimeapps.list" !! "/tmp/mimeapps.list";
    $mimeapps-path.IO.parent.mkdir unless $mimeapps-path.IO.parent.d;
    
    # Text editor selection
    my $text-editor = do given Settings.instance {
        when .get("install-vscode")  { "code.desktop" }
        when .get("install-micro")   { "micro.desktop" }
        default                      { "nvim.desktop" }
    };
    
    # Base text MIME types
    my @text-types = <
        text/plain text/x-readme text/x-install text/x-log text/x-changelog
        text/x-authors text/x-makefile text/x-cmake text/x-meson
    >;
    
    my %mime-associations;
    %mime-associations{$_} = [$text-editor] for @text-types;
    
    # PDF viewer
    if Settings.instance.get("install-xreader") {
        %mime-associations<application/pdf> = ["xreader.desktop"];
        %mime-associations<application/x-pdf> = ["xreader.desktop"];
    }
    
    # Web browser
    if Settings.instance.get("install-librewolf") {
        my @web-types = <
            text/html text/xml application/xhtml+xml application/xml
            x-scheme-handler/http x-scheme-handler/https
        >;
        %mime-associations{$_} = ["librewolf.desktop"] for @web-types;
    }
    
    # Archive manager
    if Settings.instance.get("install-engrampa") {
        my @archive-types = <
            application/x-7z-compressed application/x-7z-compressed-tar
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
            application/zip application/gzip application/bzip2
        >;
        %mime-associations{$_} = ["engrampa.desktop"] for @archive-types;
    }
    
    # Image viewer
    if Settings.instance.get("install-ristretto") {
        my @image-types = <
            image/bmp image/gif image/jpeg image/jpg image/pjpeg
            image/png image/svg+xml image/svg+xml-compressed
            image/tiff image/vnd.microsoft.icon image/x-bmp
            image/x-gray image/x-icb image/x-ico image/x-icon
            image/x-pcx image/x-png image/x-portable-anymap
            image/x-portable-bitmap image/x-portable-graymap
            image/x-portable-pixmap image/x-xbitmap image/x-xpixmap
        >;
        %mime-associations{$_} = ["org.xfce.ristretto.desktop"] for @image-types;
    }
    
    # Media player selection
    my $media-player = Settings.instance.get("install-vlc") ?? "vlc.desktop" !! 
                      Settings.instance.get("install-mpv") ?? "mpv.desktop" !! Nil;
    
    if $media-player {
        my @audio-types = <
            audio/3gpp audio/3gpp2 audio/aac audio/ac3 audio/amr
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
            audio/x-wav audio/x-wavpack
        >;
        
        my @video-types = <
            video/3gp video/3gpp video/3gpp2 video/avi video/dv
            video/fli video/flv video/mp2t video/mp4 video/mp4v-es
            video/mpeg video/mpeg-system video/mpeg1 video/mpeg2
            video/mpeg4 video/msvideo video/ogg video/quicktime
            video/vnd.mpegurl video/vnd.rn-realvideo video/webm
            video/x-avi video/x-flc video/x-fli video/x-flv
            video/x-m4v video/x-matroska video/x-mpeg video/x-mpeg-system
            video/x-mpeg1 video/x-mpeg2 video/x-mpeg4 video/x-ms-asf
            video/x-ms-asf-plugin video/x-ms-asx video/x-ms-wm
            video/x-ms-wmv video/x-ms-wmx video/x-ms-wvx video/x-msvideo
            video/x-ogm video/x-ogm+ogg video/x-theora
            video/x-theora+ogg video/x-totem-stream
        >;
        
        %mime-associations{$_} = [$media-player] for @audio-types;
        %mime-associations{$_} = [$media-player] for @video-types;
    }
    
    # Write the file
    my $content = "[Default Applications]\n";
    for %mime-associations.sort(*.key) -> $pair {
        $content ~= "{$pair.key}={$pair.value.join(';')}\n";
    }
    
    $mimeapps-path.IO.spurt($content);
    Logging.log("Created MIME applications list at $mimeapps-path");
}