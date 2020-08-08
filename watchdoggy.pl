#!/usr/bin/perl -w
# Copyright Dan Faerch, 2020.

use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;

my %opts;
my %config = (
    interval => 30,
    count    => 4,
    backoff  => 14400,
    watch    => undef,
    action   => undef
);

sub usage {
    my $err = shift;
    print "$err\n" if (defined $err);

    print <<EOD
Usage:
    -w      Watch-command - This command is run on Interval (-i) and must return zero exitcode or be deemed "down".
    -i      Interval - How often to run the Watch-command. (default=$config{interval})
    -c      Count - How many times watch-command must fail before running Action (default=$config{count})
    -a      Action - The command to run when something is deemed to be down.
    -b      Back-off - The number of seconds after executing Action, before it is allowed to do so again. (default=$config{backoff})

    Notes:
        Count will reset after Action runs. Thus a Back-off of 0 will result in Action being run every Interval*Count seconds, as long as watch command fails.

    Examples:
        This example runs "apachectl status" every 10 seconds.
        If it returns non-zero exit code 5 times in a row, then we run "apachectl restart".
        Finally, we backoff of 600 seconds (10 minutes), before it will try to do "apachectl restart" again.

        \$ ./watchdoggy.pl -i 10 -c 5 -b 600  -w "apachectl status" -a "apachectl restart"


        --

        Detect if the kernel.org doesnt contain the word "Kernel" and send a mail if that happens.
        \$ ./watchdoggy.pl -i 600 -c 3 -w "curl https://www.kernel.org | grep Kernel" -a "echo 'Kernel.org looks wrong.' | mail alert\@example.com"

        --

        Wait for a local backup to complete, then shutdown machine.
        The "find" in the example, lists files modified within the last 2 minutes, and grep matches anything. Grep will return non-zero exit code, 
        if nothing was listed. Thus, when nothing has been modified for a while in the backup folder, we will shutdown.

        \$ ./watchdoggy.pl -i 5 -c 5 -w "find /home/backups/  -mmin -2 | grep . " -a "shutdown now"

EOD
;

    exit 1;
}

getopts('w:i:c:a:b:', \%opts);
$config{watch}    = $opts{w} if defined $opts{w};
$config{interval} = $opts{i} if defined $opts{i};
$config{backoff}  = $opts{b} if defined $opts{b};
$config{count}    = $opts{c} if defined $opts{c};
$config{action}   = $opts{a} if defined $opts{a};

usage("Interval is invalid")            unless defined $config{interval} and $config{interval} > 0;
usage("Count is invalid")               unless defined $config{count}    and $config{count}    > 0;
usage("Watch-command must be defined")  unless defined $config{watch};
usage("Action must be defined")         unless defined $config{action};

sub dolog($) {
    print shift."\n";
}

my $count = 0;
my $backoff = 0;
while (1) {


    # config-count * config-interval = the time needed to determine if we need to run Action.
    # So theres is no need to execute the Watch-command before that time.
    if ($backoff < ($config{count} * $config{interval} )) {

        my $watch_res = `$config{watch}`;
        if ($? != 0) {

            $count++;
            dolog "Watch-command returned non-zero exit code";

            if ($count >= $config{count}) {
                dolog "Failed $count times";

                unless ($backoff) {
                    my $action_res = `$config{action}`;
                    dolog "Running action. Output: $action_res";

                    $count = 0;

                    if (defined $config{backoff} && $config{backoff}) {
                        $backoff = $config{backoff};
                    }
                }
            }

        } else {
            # Everthing was OK.
            $count = 0;
        }

    }

    if ($backoff) {
        dolog "Backing off for $backoff more seconds";
        $backoff--;
        sleep 1;
    } else {
        sleep $config{interval};
    }
}