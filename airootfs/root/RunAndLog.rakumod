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
use JSON::Fast;
use Logging;

sub run-and-echo(*@args, :$input, Int :$retry) is export {
    my $try-count = 0;

    sub calculate-wait-time {
        # Starts at 0.25s and doubles with each attempt: 0.25, 0.5, 1, 2, 4, 8...
        0.25 * (2 ** ($try-count - 1))
    }

    sub try-execute {
        $try-count++;
        Logging.log(@args.gist);

        if $input.defined {
            my @commands = $input.split("\n");
            Logging.log("Sending commands:");
            for @commands.kv -> $i, $cmd {
                my $display = $cmd eq '' ?? '<EMPTY>' !! $cmd;
                Logging.log("  {$i+1}. {$display}");
            }
        }

        my $result = '';
        my $proc = Proc::Async.new(:w($input.defined), |@args);

        my $promise = Promise.new;
        my $vow = $promise.vow;

        react {
            whenever $proc.stdout {
                $result ~= $_;
            }

            whenever $proc.stdout.lines {
                Logging.echo-nocolor($_);
            }

            whenever $proc.stderr.lines {
                Logging.echo-error($_);
            }

            my $process-promise = $proc.start;

            if $input.defined {
                await $proc.ready;

                start {
                    for $input.split("\n") -> $line {
                        await $proc.print($line ~ "\n");
                    }
                    $proc.close-stdin;
                }
            }

            whenever $process-promise {
                if .exitcode != 0 {
                    if $retry.defined && ($try-count < $retry) {
                        my $wait-time = calculate-wait-time();
                        Logging.log("Attempt {$try-count} of {$retry} failed. " ~
                                  "Waiting {$wait-time} seconds before next attempt...");
                        sleep $wait-time;
                        $vow.keep(try-execute());
                    } else {
                        $vow.break("Process failed with exit code {.exitcode}" ~
                                 ($retry.defined ?? " after {$try-count} attempts" !! ""));
                    }
                } else {
                    $vow.keep($result);
                }
                done;
            }
        }

        return await $promise;
    }

    return try-execute();
}

sub run-and-echo-allow-fail(*@args, :$input) is export {
    Logging.log(@args.gist);

    if $input.defined {
        my @commands = $input.split("\n");
        Logging.log("Sending commands:");
        for @commands.kv -> $i, $cmd {
            my $display = $cmd eq '' ?? '<EMPTY>' !! $cmd;
            Logging.log("  {$i+1}. {$display}");
        }
    }

    my $result = '';
    my $proc = Proc::Async.new(:w($input.defined), |@args);

    my $promise = Promise.new;
    my $vow = $promise.vow;

    react {
        whenever $proc.stdout {
            $result ~= $_;
        }

        whenever $proc.stdout.lines {
            Logging.echo-nocolor($_);
        }

        whenever $proc.stderr.lines {
            # Log stderr without coloring as error, because non-zero exit is expected here.
            Logging.echo-nocolor($_);
        }

        my $process-promise = $proc.start;

        if $input.defined {
            await $proc.ready;

            start {
                for $input.split("\n") -> $line {
                    await $proc.print($line ~ "\n");
                }
                $proc.close-stdin;
            }
        }

        whenever $process-promise {
            if .exitcode != 0 {
                Logging.log("Command exited with code {.exitcode} (non-fatal, continuing)");
            }
            $vow.keep($result);
            done;
        }
    }

    return await $promise;
}

sub run-and-log(*@args) is export {
    Logging.log(@args.gist);

    my $result = '';
    my $proc = Proc::Async.new(|@args);

    my $promise = Promise.new;
    my $vow = $promise.vow;

    react {
        whenever $proc.stdout {
            $result ~= $_;
        }

        whenever $proc.stdout.lines {
            Logging.log($_);
        }

        whenever $proc.stderr.lines {
            Logging.log($_);
        }

        whenever $proc.start {
            if .exitcode != 0 {
                $vow.break("Process failed with exit code {.exitcode}");
            } else {
                $vow.keep($result);
            }
            done;
        }
    }

    return await $promise;
}

sub query-blockdevices(Str $args) is export {
    from-json(run-and-log("lsblk", "--json", |$args.words))<blockdevices>
}

