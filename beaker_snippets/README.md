Beaker Snippets repo
====================
This repo contains snippets beaker uses to convert Anaconda kickstart
templates into actual working Anaconda kickstart files.  All machines
in the beaker cluster are considered servers and are configured as
such.

Snippets are organized according to how/when they should be applied.

Each beaker instance can have more than one lab controller, and those
controllers may be spread around the world.  So, there is a per_lab
directory that applies configurations unique to each lab controller.

Different OS major versions (rhel5, rhel7, fedora 30, etc.) might have
different package lists or other requirements.  There is a directory
called per_osmajor that is where we store those snippets.  The full
structure of this directory is
per_osmajor/<snippet group>/<OS Major>/<OS Instance>
The contents of the <OS Instance> file would be applied to all machines
installed with this <OS Major> and <OS Instance> to the portion of the
kickstart file referenced by <snippet group>.

Example: if you had the file per_osmajor/packages/rhel7/rhel7.1, it
would cause all machines installed with OS Family == rhel7 and
OS Instance == rhel7.1 to have the contents of that file applied to
the %packages portion of the Anaconda kickstart file

Finally, there is the per_system directory.  This one has multiple
naming conventions depending on what needs done.  The primary naming
convention is per_system/<kickstart section>/<fqdn> and the other
naming convention is per_system/<OS Instance>{<\_kickstart section>}/<fqdn>

NOTE: this is all straight out of Red Hat's internal tooling.  The
current beaker code is very Red Hat centric.  We realize this and it
will take time and help from the other OS vendors, but the goal is to
make this all vendor neutral.  Until then, there will be obvious
artifacts of the Red Hat centrism.
