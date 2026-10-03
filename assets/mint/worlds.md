## Writing For Several Worlds

You mint ONE language for these worlds: {{WORLDS}}. Each has its own section
above, and each section is ABSOLUTE INSIDE ITSELF AND NOWHERE ELSE: while you
write the items for one world, obey that world's section and ignore every other.
A prohibition in one section says nothing about any other world.

TAG EVERY WORLD-BOUND ITEM. A match, demand, merge or expect names its world
with @<world> right after the id:
  0.95 r1 @nixos match fact job.name => systemd.services.<self>.description "\"<value>\""
  0.95 r2 @kubenix match fact job.name => kubernetes.resources.cronJobs.<self>.metadata.name "\"<value>\""
A pattern, a because-note, a gap and the report carry NO tag:
they are the language's, shared by every world. Ids are unique across the whole
reply, so two worlds' rules never collide -- except a because-note, which
repeats the id of the item it explains.

EVERY WORLD MUST BE SERVED. Write rules for every world listed, each reading the
same facts and spending them in its own namespace. A world you leave without
rules is a world the program cannot reach.

A FACT MUST BE SPENDABLE BY EVERY WORLD. Nothing below you can convert a value:
the value grammar cannot split a string, reorder its parts, or turn one notation
into another. So where two worlds SPELL the same thing differently, the pattern
captures it in PARTS and each rule assembles its own notation. A hole may sit
inside a token, and a value may have several parts:
  0.95 p1 pattern run the image <image> every night at <hh>:<mm> => fact job.image "<image>" ; fact job.schedule "<hh> <mm>"
  0.95 r3 @kubenix match fact job.schedule => kubernetes.resources.cronJobs.<self>.spec.schedule "\"<value.2> <value.1> * * *\""
  0.95 r4 @nixos match fact job.schedule => systemd.timers.<self>.timerConfig.OnCalendar "\"*-*-* <value.1>:<value.2>:00\""
One fact, two spellings, no computation anywhere. Split exactly what the worlds
spell differently and no further: every part you create must be read by some
rule in every world, or that world's engine is refused for discarding a word the
program stated.

AN EXPECT OVER A SPLIT FACT STATES THE TEXT ITS OWN WORLD ASSEMBLES. A contract
compares the option's text against the value the fact carries, and a
several-part value read WHOLE is its parts joined by a space -- which no world's
notation contains, so a whole-value expect over a split fact can never hold and
lips refuses it. Where the rule ASSEMBLES the text, the expect states that same
text, with the same template, and the two are compared for equality:
  0.95 a1 @nixos expect systemd.timers.<self>.timerConfig.OnCalendar from job.schedule is "*-*-* <value.1>:<value.2>:00"
  0.95 a2 @kubenix expect kubernetes.resources.cronJobs.<self>.spec.schedule from job.schedule is "<value.2> <value.1> * * *"
Where a world writes ONE part into an option that holds only that part, name the
part instead:
  0.95 a3 @nixos expect systemd.services.<self>.environment.HOUR from job.schedule#1

WHERE A WORLD HAS NO PLACE FOR A FACT ANOTHER WORLD NEEDS, DECLARE IT. Some
facts belong to only some worlds: a Kubernetes pod needs a container image, and
a machine that runs the script directly has none. The world with no place for it
says so, with the reason, in its own rules:
  0.9 i1 @nixos ignore fact job.image "a machine runs the script directly, so there is no image"
Every fact must be placed by a rule or declared this way in every world, so
nothing is dropped silently. You may NOT ignore a fact no world places: that
fact is dead, the language reads a word of the program and throws it away, and
lips refuses the whole mint for it. Prefer a fact every world can spend over an
asymmetry -- an image is genuinely one world's, a schedule is not.

WHERE A WORLD NEEDS A FACT THE PROGRAM DOES NOT STATE, DEMAND IT. Write that
world's demand and stop; never invent the value. A Kubernetes pod needs a
container image and a NixOS unit does not, so the image is a kubenix demand:
  0.95 q1 @kubenix demand job.image "which container image should the run use?"
The program's author then states it in one sentence, and until they do, that
world alone is incomplete while the others still build. A value you invent is
worse than a question you ask: it passes every gate and ships something nobody
wrote down.
