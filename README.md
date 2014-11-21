# copy-parallel and verify-parallel
## Faster tools to copy drives and verify the copies

These tools are intended to be used with special device files, like so:

    copy-parallel /dev/disk1 /dev/disk2
    verify-parallel /dev/disk1 /dev/disk2

The first command will copy all of the bytes from /dev/disk1, until that file is exhausted, into /dev/disk2.

The second command will compare the common prefix of both files (if one is shorter, anything beyond that length in the longer file is not considered) and report if it finds a difference.

copy-parallel currently emits a progress update on stdout every two seconds, whereas verify-parallel emits a single report at the end (whether “the end” is after successfully proving both files equal, or after encountering a difference).

### Ways in which these programs presume you are using them on devices

- Unlike cp, copy-parallel will not attempt to create the destination file.
- copy-parallel offers no functionality for copying directories or symbolic links. Given a symbolic link as the source, it will (probably; I haven't tested this) copy the contents of the original file.
- verify-parallel compares 10 MB chunks. If there is a difference anywhere in a given pair of 10 MB chunks, it will tell you that there is a difference somewhere in those 10 MB. (When you're copying a device, *any* difference is a problem; the value or exact position of the difference is unimportant.)

### Why are they better?

They're faster.

Both programs use Grand Central Dispatch to minimize how much waiting on I/O they do. copy-parallel writes to the destination while it reads from the source; verify-parallel reads the next pair of chunks while the pair before is being compared.

YMMV, but on my system copying between hard drives via USB 2.0, dd copied at ~4,500,000 bytes per second and copy-parallel copied at ~4,600,000 bytes per second, and GNU cmp finished in 392,101 seconds after verify-parallel finished in 382,073 seconds.

They're also simpler (in interface, at least). dd and cmp provide various options for various purposes, whereas each of these programs does exactly one thing.
