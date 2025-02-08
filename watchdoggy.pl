#!/usr/bin/perl -w
# Copyright Dan Faerch, 2020 - GPL-3.0 license - https://github.com/dfaerch/watchdoggy
use strict;
use warnings;
use Getopt::Std;
use IPC::Open3;
use Symbol 'gensym';
use IO::Select;

my %opts;
getopts('w:i:c:a:b:s:v:e:', \%opts);
my %config = (
    interval    => 30,
    count       => 4,
    backoff     => 14400,
    watch       => undef,
    action      => undef,
    verbose     => 1,
    stdin_lines => undef,  # Max number of lines to buffer from STDIN
    expected_ok => 0,      # Expected exit code for "all good"
);

$config{watch}    = $opts{w} if defined $opts{w};
$config{interval} = $opts{i} if defined $opts{i};
$config{backoff}  = $opts{b} if defined $opts{b};
$config{count}    = $opts{c} if defined $opts{c};
$config{action}   = $opts{a} if defined $opts{a};
$config{verbose}  = $opts{v} if defined $opts{v};
$config{stdin_lines} = $opts{s} if defined $opts{s};
$config{expected_ok} = $opts{e} if defined $opts{e};

sub usage {
    my $err = shift;
    print "$err\n" if defined $err;
    print <<'EOD';
Usage:
    -w      Watch-command. This command is run every Interval seconds and must return an OK exit code (see -e).
    -i      Interval - seconds between watch-command executions (default=30).
    -c      Count - number of consecutive failures before running Action (default=4).
    -a      Action - command to run when watch-command fails sufficiently.
    -b      Back-off - seconds to wait after running Action (default=14400).
    -s      STDIN mode - if defined, we read from STDIN, maintaining a buffer of at most n lines. Watch-command
            is run over this buffer only. And only at -i interval.
    -e      Expected OK exit code - The exit code that indicates everything is fine (default=0).
    -v      Verbosity - 0=silent, 1=normal, 10=debug.



Examples:

    First example runs "apachectl status" every 10 seconds.
    If it returns non-zero exit code 5 times in a row, then we run "apachectl restart".
    Finally, we backoff of 600 seconds (10 minutes), before it will try to do "apachectl restart" again.
      $ ./watchdoggy.pl -i 10 -c 5 -b 600 -w "apachectl status" -a "apachectl restart"

    Pipe a live logfile in, keeping only the last 100 lines of input in buffer. Ever 10 seconds, grep that buffer for "ERROR".
    grep exit 1 if not found, so we define -e 1, meaning, if ERROR was not found in buffer, it doesnt count. 
      $ tail -f logfile | ./watchdoggy.pl -s 100 -i 10 -c 5 -b 600 -w -e 1 "grep -q 'ERROR'" -a "systemctl restart myservice"

    Monitor stdout inside a Docker or Podman container for something spefic and take action based on it.
      $ tail -f /proc/1/fd/1 | /watchdoggy.pl -s 10 -i 60 -c 2 -b 600  


    Note: You do not get realtime reaction to stdin. This tool is explicitly made for the opposite: Analysing a smaller sample
    of data, at a defined interval and take an action if enough matches are made.

EOD
    exit 1;
}

usage("Interval is invalid")           unless defined $config{interval} and $config{interval} > 0;
usage("Count is invalid")              unless defined $config{count}    and $config{count}    > 0;
usage("Watch-command must be defined") unless defined $config{watch};
usage("Action must be defined")        unless defined $config{action};

sub dolog($$) {
    my ($level, $msg) = @_;
    print "$msg\n" if $config{verbose} >= $level;
}

sub run_watch_with_stdin {
    my ($cmd, $buffer_ref) = @_;
    my $err = gensym;
    my $pid = open3(my $child_in, my $child_out, $err, $cmd);

    # Ensure command always gets input
    if (@$buffer_ref) {
        print $child_in $_ for @$buffer_ref;
    } else {
        print $child_in "\n";  # Prevent failure due to empty input
    }

    close $child_in;
    my $output = do { local $/; <$child_out> };
    close $child_out;
    waitpid($pid, 0);
    my $exit_code = $? >> 8;
    return ($output, $exit_code);
}

my $count   = 0;
my $backoff = 0;

if (defined $config{stdin_lines}) {
    my @buffer;
    my $sel = IO::Select->new();
    $sel->add(\*STDIN);
    my $time_counter = 0;

    while (1) {
        while (my @ready = $sel->can_read(0)) {
            my $line = <STDIN>;
            last unless defined $line;
            push @buffer, $line;
            shift @buffer while scalar(@buffer) > $config{stdin_lines};
        }

        if ($backoff) {
            dolog(10, "Backing off for $backoff more seconds");
            $backoff--;
        }
        else {
            $time_counter++;
            if ($time_counter >= $config{interval}) {
                $time_counter = 0;
                my ($watch_res, $watch_exit) = run_watch_with_stdin($config{watch}, \@buffer);
                
                if ($watch_exit != $config{expected_ok}) {
                    $count++;
                    dolog(1, "Watch-command returned unexpected exit code: $watch_exit (Expected: $config{expected_ok})");
                    if ($count >= $config{count}) {
                        dolog(10, "Failed $count times");
                        unless ($backoff) {
                            my $action_res = `$config{action}`;
                            dolog(1, "Running action. Output: $action_res");
                            $count = 0;
                            if ($config{backoff}) {
                                $backoff = $config{backoff};
                                dolog(1, "Backing off for $backoff seconds");
                            }
                        }
                    }
                }
                else {
                    $count = 0;
                }
            }
        }
        sleep 1;
    }
}
else {
    while (1) {
        if ($backoff < ($config{count} * $config{interval})) {
            my $watch_res = `$config{watch}`;
            my $watch_exit = $? >> 8;

            if ($watch_exit != $config{expected_ok}) {
                $count++;
                dolog(1, "Watch-command returned unexpected exit code: $watch_exit (Expected: $config{expected_ok})");
                if ($count >= $config{count}) {
                    dolog(10, "Failed $count times");
                    unless ($backoff) {
                        my $action_res = `$config{action}`;
                        dolog(1, "Running action. Output: $action_res");
                        $count = 0;
                        if ($config{backoff}) {
                            $backoff = $config{backoff};
                            dolog(1, "Backing off for $backoff seconds");
                        }
                    }
                }
            }
            else {
                $count = 0;
            }
        }
        if ($backoff) {
            dolog(10, "Backing off for $backoff more seconds");
            $backoff--;
            sleep 1;
        }
        else {
            sleep $config{interval};
        }
    }
}
