# watchdoggy
Simple command line watchdog-like tool, that checks for a condition and then execute a command if met. 

## Usage

```
    -w      Watch-command - This command is run on Interval (-i) and must return zero exitcode or be deemed "down".
    -i      Interval - How often to run the Watch-command. (default=30)
    -c      Count - How many times watch-command must fail before running Action (default=4)
    -a      Action - The command to run when something is deemed to be down.
    -b      Back-off - The number of seconds after executing Action, before it is allowed to do so again. (default=14400)

    Notes:
        Count will reset after Action runs. Thus a Back-off of 0 will result in Action being run every Interval*Count seconds, as long as watch command fails.

    Examples:
        This example runs "apachectl status" every 10 seconds.
        If it returns non-zero exit code 5 times in a row, then we run "apachectl restart".
        Finally, we backoff of 600 seconds (10 minutes), before it will try to do "apachectl restart" again.

        $ ./watchdoggy.pl -i 10 -c 5 -b 600  -w "apachectl status" -a "apachectl restart"


        --

        Detect if the kernel.org doesnt contain the word "Kernel" and send a mail if that happens.
        $ ./watchdoggy.pl -i 600 -c 3 -w "curl https://www.kernel.org | grep Kernel" -a "echo 'Kernel.org looks wrong.' | mail alert@example.com"

        --

        Wait for a local backup to complete, then shutdown machine.
        The "find" in the example, lists files modified within the last 2 minutes, and grep matches anything. Grep will return non-zero exit code, 
        if nothing was listed. Thus, when nothing has been modified for a while in the backup folder, we will shutdown.

        $ ./watchdoggy.pl -i 5 -c 5 -w "find /home/backups/  -mmin -2 | grep . " -a "shutdown now"
```