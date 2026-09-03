; sd.iss - Inno Setup script for SD on Windows
;
; Build:
;   cd sdb_ai/sd64
;   make sd
;   python3 gplbld/stage.py --stage ../../stage --force --bootstrap
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DStage=..\..\stage gplbld\sd.iss
;
; This packages the tree gplbld/stage.py produces.  It does not build anything
; and it must not: the staged tree is already compiled AND already bootstrapped,
; which is what lets an install be a file copy needing neither Python nor a
; compiler on the target.  See PROJECT_STATUS.md 5.16.
;
; THE LAYOUT IS LOAD-BEARING, NOT TIDINESS.  Binaries go in
; C:\Program Files\SD\usr\bin, two components down, because shipping
; msys-2.0.dll beside sd.exe relocates the entire POSIX namespace: the runtime
; derives its root by stripping TWO components from the directory holding the
; DLL.  usr\bin puts the root on C:\Program Files\SD\.  One level up and the
; root becomes C:\Program Files\, which would mean creating C:\Program Files\dev.
; etc\fstab then maps /dev/shm back out to C:\ProgramData\SD\shm, because
; shm_open() creates files there and Program Files is read-only to ordinary
; users.  Both are measured, not guessed - the trap is in PROJECT_STATUS.md 6.
;
; Do not "simplify" this by putting the executables directly in the app folder.

#ifndef Stage
  #define Stage "..\..\stage"
#endif
#ifndef AppVer
  #define AppVer "W1.0-0"
#endif

; 1 Sep 26 - THE PRODUCT IS "SD Core", AND THE WIZARD SAID "SD".  Owner, on
; reading the caption during the guest run: "the title of the sd setup dialog
; should be SD Core W1.0-0 (the word Core is missing)".  sd.exe's own banner has
; said "SD Core for Windows" throughout, so the installer was the odd one out.
; AppVerName is {#AppName} {#AppVer}, so this one define fixes the caption AND
; the Apps & Features entry, which read "SD W1.0-0".
;
; WHAT ELSE MOVES, TRACED RATHER THAN ASSUMED.  DefaultGroupName is {#AppName}
; too, so a FRESH install's Start Menu folder becomes "SD Core"; an upgrade
; keeps the old one, because UsePreviousGroup defaults to yes.  DefaultDirName
; is the literal {autopf}\SD and does NOT move - the install path stays
; C:\Program Files\SD, which the disclosure page promises is fixed.  AppId is
; untouched, so upgrades are still recognised.  The two scripts that find the
; install by name both still match: VerifyInstall1.ps1:252 and sdtestuser.ps1
; use -like 'SD *', and capture-state.ps1:217 uses -match 'SD'.
#define AppName    "SD Core"
#define AppPublisher "String Database"
#define DataDir    "{commonappdata}\SD"

[Setup]
AppId={{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}
AppName={#AppName}
AppVersion={#AppVer}
AppVerName={#AppName} {#AppVer}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\SD
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; 22 Aug 26 - THE INSTALL LOCATION IS NOT A CHOICE.  Owner's decision: the DATA
; tree is not offered as one - DataDir is #defined above as {commonappdata}\SD,
; a compile-time constant with no wizard page - so offering an alternative to
; {autopf}\SD was an asymmetry with nothing behind it.  A user who moved the
; program directory got a half-movable install: the programs somewhere of their
; choosing, the data always in C:\ProgramData\SD.
;
; AND IT WAS NOT COST-FREE, WHICH IS HOW IT WAS FOUND.  Twenty-one verify
; scripts locate the install as "$env:ProgramFiles\SD", and assert-current.ps1:40
; hardcodes the literal "C:\Program Files\SD\usr\bin\sd.exe" - so on an install
; the user had moved, the staleness guard would compare against a path that does
; not exist and the whole suite would fail without saying why.  Inno DOES record
; the real location (HKLM ...\Uninstall\{AppId}_is1, InstallLocation, measured
; 22 Aug), so teaching all twenty-two to read it was possible; removing the
; choice removes the class of fault instead.
;
; UsePreviousAppDir=no MATTERS AS MUCH AS DisableDirPage.  Without it Inno
; reuses the directory a PREVIOUS install recorded, so a machine that once
; installed elsewhere would keep doing so and the pin would silently not apply
; there - which is the one case this is for.
;
; /DIR= ON THE COMMAND LINE STILL OVERRIDES BOTH.  That is Inno's behaviour and
; is left alone: it is an explicit act by somebody who has read this far, not a
; wizard page a user clicks past.
DisableDirPage=yes
UsePreviousAppDir=no
OutputBaseFilename=sd-setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

; 02 Sep 26 - WINDOWS 10 AND 11, NOTHING EARLIER.  Owner's ruling, 2 Sep 2026:
; "I don't believe in supporting versions no longer supported by the vendor",
; and then, on 10: "just because 10 is still in extended support".
;
; ***SO THE FLOOR IS A SUPPORT DATE, NOT A TECHNICAL LIMIT, AND IT WILL MOVE.***
; Nothing here needs anything Windows 10 lacks; 10 is admitted because Microsoft
; still supports it and drops out when that ends.  Whoever raises this to 11 is
; applying the rule rather than changing it - do not go looking for the feature
; that stopped working, because there is not one.
;
; 10.0 ADMITS BOTH 10 AND 11, which is not obvious: Windows 11 reports itself as
; NT 10.0 and is told apart by build number, not version.  So one directive
; covers both and excludes 8.1 and earlier.
;
; IT WAS ABSENT UNTIL NOW, which meant Inno's own default applied - Windows 7
; SP1 - so the installer had been promising four unsupported versions it was
; never tested on.  Found 2 Sep 2026 while checking whether TaskDialogMsgBox
; could fall back to a plain MsgBox on an older Windows; it cannot arise here,
; and the check turned up this instead.
MinVersion=10.0

; Creating C:\Program Files\SD and writing the ACLs on C:\ProgramData\SD both
; need an elevated token, and so does installing OpenSSH Server.  Inno asks for
; it through UAC, which is why the installer can do things a normal SD session
; cannot - creating Windows accounts among them.
PrivilegesRequired=admin

; Inno warns that {username} is a per-user value being used in an
; administrative install, and it is right to.  We mean it, and the limit is
; understood: {username} is whoever authenticated the UAC prompt.  When an
; administrator installs SD for themselves - the common case, and the one the
; opt-in ssh checkbox is aimed at - that is the right person.  When a STANDARD
; user runs setup and an administrator types credentials, it is the
; administrator who joins sdusers and the standard user who does not, and they
; will find SD cannot open its files.  There is no reliable way to ask Inno who
; is at the keyboard, so the final message tells the user how to add anyone
; else - with CREATE.ACCOUNT, which is the only answer it gives.  It used to
; offer "net localgroup sdusers <name> /add" as a fallback for somebody who
; already has a Windows account; that was dropped on 15 Aug 2026 because it does
; not work.  See the comment on the MsgBox itself.
UsedUserAreasWarning=no

; The server is PE32+ and the MSYS2 runtime is 64 bit.  There is no 32 bit build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; The PATH entry below is a machine environment change; without this the
; setting does not reach already-running processes.
ChangesEnvironment=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; 1 Sep 26 - reworded from Inno's stock SelectTasksLabel2 at the owner's request.
; [name] renders as AppName, "SD Core".  Must sit after [Languages], which is
; what it overrides.
SelectTasksLabel2=Select additional tasks for Setup to perform while installing [name], then click Next.

[Tasks]
Name: "addtopath"; Description: "Add SD Core to the system PATH so ""sd"" runs from any directory"; \
    GroupDescription: "1)  System integration:"

; ===========================================================================
; ssh IS TWO SEPARATE CHOICES AGAIN, AND THE SECOND DEPENDS ON THE FIRST.
; Owner's ruling, 30 Aug 2026, superseding the 16 Aug 2026 decision that made
; the server unconditional:
;
;   "if an ssh server is installed, the user should have a separate choice to
;    allow remote access.  If a server is not installed the user should have
;    two choices, install the server, and allow remote access.  Allowing remote
;    access should not be an option if they choose not to install the ssh
;    server."
;
; THAT IS THREE REQUIREMENTS AND THEY DO NOT FIT ONE [Tasks] ENTRY, which is
; why there are four below for what a reader sees as at most two boxes.
;
;   server ABSENT   -> "sshserver" (install it) and, INDENTED UNDER IT,
;                      "sshserver\sshremote" (allow remote access).
;   server PRESENT  -> the remote box alone, because there is nothing to
;                      install; this is PRE_RELEASE 76, where the installer
;                      previously asked nothing at all and set no firewall.
;
; ***THE DEPENDENCY IS INNO'S, NOT OURS, AND THAT IS THE POINT.***  A child
; task written "parent\child" is greyed AND unchecked by Inno whenever the
; parent is unchecked.  So "allowing remote access should not be an option if
; they choose not to install the ssh server" is enforced as a UI STATE the
; reader can see, not as an error message after the fact.  Do not replace this
; with a validation check in NextButtonClick: that would let the box be ticked
; and then complain, which is the thing the owner asked against.
;
; WHY A CHILD CANNOT SERVE BOTH CASES.  Inno does not create a child whose
; parent's Check is False, so the "server present" case cannot reuse
; sshserver\sshremote - the parent is not there to hang it on.  Hence the two
; flat entries below it, whose Checks are mutually exclusive with the child's.
;
; ***AND THE TWO FLAT ONES DIFFER ONLY IN THEIR DEFAULT, WHICH IS READ FROM THE
; MACHINE.***  Owner's ruling, 30 Aug 2026, on what an unticked box should do to
; an ssh server SD did not install: the box shows the CURRENT firewall scope, so
; leaving it alone changes nothing in either direction.  Ticking an unticked box
; opens; unticking a ticked box restricts.  The alternative - always defaulting
; unchecked and restricting on apply - would silently loopback-lock the ssh a
; site already uses for its own administration, because OpenSSH-Server-In-TCP is
; Windows' shared rule and not one of ours.  SshCurrentlyOpen reads it.
;
; THE GROUP IS "ssh:" RATHER THAN "Remote access:" because the first box is not
; about remote access at all - it is about whether the service exists.
; ***THE TWO FLAGS BELOW ARE THE WHOLE OF THE THREE STATES, AND LEAVING THEM OFF
; PRODUCED TWO WRONG ONES.  Measured 30 Aug 2026 by the owner at the wizard, and
; then read out of Inno's own help (ISetup.chm, "Tasks section") rather than
; guessed a second time:***
;
;   dontinheritcheck - "Specifies that the task should not automatically become
;                       checked when its parent is checked."
;   checkablealone   - "Specifies that the task can be checked when none of its
;                       children are.  BY DEFAULT, if no Tasks parameter
;                       directly references the task, unchecking all of the
;                       task's children will cause the task to become
;                       unchecked."
;
; WITHOUT THEM THE OWNER SAW EXACTLY WHAT THE DEFAULTS PROMISE: ticking the
; server ticked the remote box with it, and unticking the remote box untick the
; SERVER - so "install the server, no remote access" could not be expressed at
; all.  The three states he asked for are:
;
;   parent off                -> no server, and the child cannot be selected
;                                ("A child task can't be selected if its parent
;                                task isn't selected" - same help topic)
;   parent on, child off      -> server, no remote access   <- needs BOTH flags
;   parent on, child on       -> server with remote access
;
; ***AND THE `Check:` ON THE [Run] ENTRY IS NOT THE `Tasks:` PARAMETER THE HELP
; MEANS.***  The exemption reads "unless a Tasks parameter DIRECTLY REFERENCES
; the parent task"; install-ssh.ps1 carries `Check: SshServerWanted`, which is a
; Check and not a Tasks parameter, so the exemption does not apply here and
; checkablealone is doing real work rather than being belt-and-braces.
; 1 Sep 26 - OPT-IN, NOT OPT-OUT, AND THE COST IS ON THE LABEL.  Owner's ruling,
; 1 Sep 2026: do not tick this by default.  Installing the server is a
; Feature-on-Demand download from Windows Update that is a few minutes on a fast
; machine and up to about an hour on a slow one, and forcing that on every
; install - for a server the administrator may not need, since an administrator
; reaches SD Core by elevation rather than over ssh - is a deal-breaker for an
; open-source tool.  So it defaults OFF (Flags: unchecked) and the cost lives in
; the Description, at the choice, rather than on a page of its own: the owner's
; word, "I don't like having the explanation separate from the choice."
;
; LEAVING IT OFF DOES NOT MAKE ACCOUNTS UNUSABLE, and the label must not imply it
; does.  Owner's correction, 1 Sep 2026: an account can also be reached through
; the API - a separate port-4243 listener (its own choice below), NOT carried
; over ssh (sd.iss:349, "the ssh tunnel is no longer part of the design") - so
; creating accounts is independent of whether an ssh server exists.  What ssh
; provides is interactive sign-in over "ssh localhost" or remotely.  The older
; "accounts sign in over ssh and nothing else" premise is wrong and is filed
; separately.  PRE_RELEASE_FIXES 124.
Name: "sshserver"; Description: "Install the OpenSSH server so SD Core accounts can sign in over ssh (they can also be reached through the API instead) - it downloads from Windows Update and can take several minutes, up to about an hour on a slow machine"; \
    GroupDescription: "2)  SSH Server - Availability and Access:"; Flags: checkablealone unchecked; \
    Check: SshServerAbsent

Name: "sshserver\sshremote"; Description: "Let other computers on your network connect to this one over ssh (port 22)"; \
    Flags: unchecked dontinheritcheck; \
    Check: SshServerAbsent

; PRESENT AND CURRENTLY LOOPBACK-ONLY - default unticked, so doing nothing keeps
; it loopback-only.
Name: "sshremoteshut"; Description: "Let other computers on your network connect to this one over ssh (port 22)"; \
    GroupDescription: "2)  SSH Server - Availability and Access:"; Flags: unchecked; \
    Check: (not SshServerAbsent) and (not SshCurrentlyOpen)

; PRESENT AND CURRENTLY OPEN - default TICKED, so doing nothing leaves the
; site's existing exposure exactly as it was.  Unticking it is then a deliberate
; act, and it is the one PRE_RELEASE 76 asked for: "the ssh server is installed
; but the user might want it limited to loopback so still want to deny remote
; access."
Name: "sshremoteopen"; Description: "Let other computers on your network connect to this one over ssh (port 22)"; \
    GroupDescription: "2)  SSH Server - Availability and Access:"; \
    Check: (not SshServerAbsent) and SshCurrentlyOpen

; ===========================================================================
; 25 Aug 26 - THIS IS NO LONGER A TASK.  THERE IS NO CHECKBOX.  The work still
; happens on every install; what has gone is the pretence that it was optional.
;
; OWNER'S REASON, AND IT IS THE WHOLE OF IT: "My suggestion would be to change
; it from a tick box that can't be ticked off, to just a statement without a
; tick box.  Seeing a tick box a user just assumes it is an option."  A
; checkbox is a promise that unticking is supported.  This was ticked by
; default and expected never to be unticked, which made the checkbox the
; misleading part - not the wording, which 5.9's option C had already fixed.
;
; WHAT MADE IT SAFE TO DROP THE OPT-OUT.  The opt-out existed for the machine
; that already had an ssh server somebody else configured.  Since the same day,
; InitializeSetup REFUSES TO INSTALL on such a machine at all
; (ssh-preflight.ps1), so that machine no longer reaches this page.  On the
; machine that is left - Windows' own server, configured by nobody but SD -
; there was never a case for declining.
;
; It is disclosed on the "Before you install" page instead, beside
; "OPENSSH SERVER - INSTALLED, NOT OPTIONAL", which is where the things SD does
; without asking are listed.
;
; ApplyAllowGroups no longer tests WizardIsTaskSelected: see its own comment.
; The reasoning below is kept because it is why the step exists and what it
; costs, none of which changed.
; ===========================================================================
;
; THE SECOND LAYER OF 5.6.2.  PROMOTED FROM A SUBTASK on 16 Aug 2026, because
; the parent it hung off no longer exists.
;
; ITS Check IS GONE - owner's decision, 21 Aug 2026, and the comment it replaces
; said "Do not remove it".  That reasoning was right about the risk and wrong
; about the mechanism, and the mechanism made the task a ONE-SHOT:
;
;   - Uninstall ALWAYS strips SD's block (RemoveAllowGroups, below).
;   - SshServerAbsent asks whether sshd.exe was missing BEFORE THIS INSTALL
;     BEGAN - SshWasAbsent, set in InitializeSetup.
;   - SD'S OWN FIRST INSTALL PUTS sshd.exe THERE FOR EVER.
;
; So it worked exactly once, on a machine with no ssh server, and every cycle
; since removed it and could not re-apply it.  Found 21 Aug 2026 by
; verify-routes.ps1: 30/32, and the two failures were this - sshd_config stock,
; no AllowGroups and no ForceCommand.  THE ForceCommand HALF IS THE SHARP ONE:
; without it an ssh session lands at a PowerShell prompt instead of in SD, so an
; account confined to sdsshonly gets a shell on the server - the thing the
; confinement exists to prevent, arriving by the far door.
;
; AND IT IS ON BY DEFAULT - owner's decision, 21 Aug 2026, the second change to
; this task that day.  "Flags: unchecked" is gone.
;
; WHAT THAT REVERSES, AND IT IS WORTH BEING HONEST ABOUT.  When the Check came
; off earlier the same day, the note here said 5.9 - "we never reconfigure an
; ssh server we did not install" - was carried by Flags: unchecked, because
; nothing happened unless an administrator ticked a box.  That is no longer
; true: A SILENT INSTALL NOW APPLIES THIS, since an Inno task without
; "unchecked" is selected in silent mode too.
;
; WHAT STILL CARRIES IT IS allow-ssh-groups.ps1's SECOND REFUSAL, and it is the
; stronger of the two guards rather than the weaker: it reads sshd_config and
; REFUSES if an AllowGroups, AllowUsers, DenyGroups or DenyUsers line is already
; there.  So somebody else's access policy is never widened, replaced or merged
; into - which is the thing 5.9 exists to protect.  What has gone is the
; protection against SD configuring a server on a machine that has NO policy at
; all, and on such a machine SD's model is the only model there is.
;
; THE COST IS STATED IN THE DESCRIPTION AND HAS NOT CHANGED: ForceCommand stops
; scp and sftp working FOR EVERYONE on the machine.  It is now the default
; rather than a choice, so the description is the only warning an administrator
; gets before accepting it, and the box can still be UNticked.
;
; Limiting ssh is about SD's access model rather than about who installed the
; server, which is why the Check went; making it the default says that model is
; what SD expects to be running under rather than an option somebody remembers.
;
; SshWasAbsent IS STILL RIGHT FOR THE OTHER TWO USES and keeps its Check: the
; firewall step and the "did SD put this here" report are both genuinely about
; whose server it is.
;
; TWO BACKSTOPS REMAIN IN allow-ssh-groups.ps1, and the second is the one that
; matters now: it refuses if sshd_config ALREADY says who may connect, so it
; cannot silently widen or replace somebody else's policy.
;
; The deny rights say where an account may NOT log in.  This says who may ssh at
; all: two independent controls rather than one.  Still off by default, because
; it writes to a file outside SD's own tree.
;
; THE LIST INCLUDES ADMINISTRATORS.  Without that the machine's own
; administrator loses ssh the moment this is applied - the caution in 5.6.2, and
; the reason this is offered rather than done silently.  allow-ssh-groups.ps1
; resolves the name from S-1-5-32-544 rather than writing "Administrators",
; which would be wrong on a localised Windows.
;
; THE DESCRIPTION NAMES scp AND sftp because the ForceCommand half of that
; script stops them working for everyone, which follows from the decision and is
; not a side effect that was missed - but it is not something to discover after
; ticking a box that only mentioned AllowGroups, which is what it used to say.
; 24 Aug 26 - DESCRIPTION LEADS WITH THE DESTRUCTIVE EDGE.  On a machine that
; already has sshd and uses it - for scp, for sftp, for a shell - ticking this
; without reading breaks that use silently.  The 21 Aug flip made this default-
; ticked; option C from PROJECT_STATUS.md 5.9 keeps that (Flags: unchecked
; would trade one problem for a weaker default; SshWasAbsent would reintroduce
; the "task a one-shot" trap allow-ssh-groups.ps1:22-27 records), so the
; warning has to be in the description itself, and it has to be the first
; thing read.  Previous wording was "Limit ssh to SD users and administrators,
; and put every ssh session straight into SD (disables scp and sftp)" - the
; sharp edge was at the end, past a comma and inside a parenthesis, which was
; exactly what a reader who scanned would skip.
; (no Name: line here on purpose - see the 25 Aug 26 note at the top of this
;  block.  The wording that used to be the Description now appears on the
;  "Before you install" page as a statement.)

; THE API PORT.  Owner's decision, 21 Aug 2026: the API is reached AT THE PORT,
; normally 4243, and the ssh tunnel is no longer part of the design (8, posture
; B reversed).  gplsrc/sdwind.c binds every interface and gplbld/stage.py ships
; APIPORT=4243 active, so the firewall rule is what decides who may reach it.
;
; ===========================================================================
; 25 Aug 26 - OPT-IN NOW.  Owner's decision, reversing the default this block
; argued for.  The paragraph it reverses is kept below rather than deleted,
; because the argument was a real one and a future session should be able to
; see what was traded away.
;
; WHAT DECIDED IT.  The two remote options defaulted OPPOSITE ways - ssh off
; unless ticked, the API on unless cleared - and both open a port to the local
; network.  That asymmetry was found while writing the stand-alone mode page,
; when a summary line describing both as "optional" turned out to be true and
; still misleading.  A default that has to be explained in the sentence next to
; it is the wrong default; the owner's own rule about the limitssh checkbox -
; "seeing a tick box a user just assumes it is an option" - is the same
; instinct pointing the other way.
;
; WHAT IT COSTS, STATED PLAINLY, because the superseded argument below is right
; about it: somebody who wanted a remote API client and did not read the task
; list now gets "cannot connect".  ApplyApiFirewall's not-wanted branch already
; prints the exact command to open it later, and the mode page names the API as
; one of the things a full installation is FOR, so it is a discoverable failure
; rather than a silent one.
;
; Nothing else changed: ApplyApiFirewall already scoped the rule to loopback
; when the task was not selected, exactly as ApplySshFirewall does.
; ---------------------------------------------------------------------------
; SUPERSEDED 25 Aug 26, kept for its reasoning:
;
;   TICKED BY DEFAULT, AND IT IS THE ONE TASK HERE THAT DIFFERS FROM sshremote
;   ON PURPOSE.  sshremote is unchecked because ssh has a use for somebody who
;   never wants a remote connection at all - a local user reaches SD by ssh'ing
;   to localhost, which is the case that made the ssh server mandatory.  THE API
;   HAS NO SUCH CASE after this change: its whole purpose is a client on another
;   machine, so an install that leaves the port firewalled off ships a feature
;   that does not work, with "cannot connect" as the symptom of not having read
;   the task list.  That is the same argument gplbld/stage.py records for APIPORT
;   itself being active.
; ===========================================================================
; 26 Aug 26 - GATED, matching sshremote two entries above.  A stand-alone
; install writes an sd.conf with no APIPORT, so SD opens no socket at all and
; ApplyApiFirewall exits: the box could never do anything.  Offering it two
; screens after the mode page promised no port was opened is the fault, not
; the firewall rule.  sshremote's Check also carries SshServerAbsent; there is
; no equivalent condition here, so this one is the mode alone.
; 30 Aug 26 - THIS IS A SERVICE SWITCH NOW, NOT A FIREWALL SWITCH.
; PRE_RELEASE_FIXES 75, the owner's ruling of 30 Aug 2026: "the api box
; unchecked should mean not provide the service at all - the port should not be
; left open."  So it no longer decides who may reach a listener that exists
; regardless; it decides whether SD opens one at all, by choosing which sd.conf
; is installed ([Files]).  The firewall then FOLLOWS the service rather than
; gating it.
;
; NO Check: AT ALL ANY MORE.  It used to carry "not StandaloneChosen"; the mode
; that condition referred to is gone, and this box is what replaced it.
; 30 Aug 26 - THE THIRD STATE IS BACK, AS A CHILD TASK.  PRE_RELEASE_FIXES 75.
; The ruling above stands untouched - an unticked parent still means SD opens no
; socket at all - and the cost the entry recorded is what this removes: with one
; box, a program on THIS machine talking to 127.0.0.1:4243 had to tick it, and
; ticking it also opened the port to the network.
;
; ***THE SHAPE IS THE ONE ALREADY RULED FOR ssh, NOT A NEW IDEA.***  sshserver /
; sshremote is a parent and a child, and Inno greys and unchecks a child whose
; parent is unchecked - so "you cannot let the network in without providing the
; service" is a state the reader SEES rather than a message after the fact.
;
; AND THE DEFAULT MOVES THE SAFE WAY: ticking the parent alone now leaves the
; rule RESTRICTED to this computer.  Opening 4243 to the network is a second,
; deliberate click rather than a side effect of wanting the API at all.
; remote.api on|local|off (entry 78) changes it afterwards either way.
; 31 Aug 26 - THE THREE FLAGS THAT MAKE THE PAIR BEHAVE.  PRE_RELEASE_FIXES 85,
; RE-OPENED because the entry was struck on "ISCC compiled it" and the owner
; then watched the wizard: "the two API entries are linked together like the ssh
; entries were before they were fixed.  If you select or delete one, you select
; or delete both."
;
; ***THAT REVERSED THE ENTIRE POINT OF 85.***  Without dontinheritcheck, Inno
; ticks the child whenever the parent is ticked - so asking for the API re-ticked
; "let other computers reach it" and the default opened 4243 to the network
; again, which is the exact cost this entry exists to remove.
;
; THE SAME TWO FLAGS 67 ALREADY PAID FOR, READ OUT OF ISetup.chm RATHER THAN
; ASSUMED A THIRD TIME.  dontinheritcheck - "the task should not automatically
; become checked when its parent is checked".  checkablealone - "the task can be
; checked when none of its children are", because by default "unchecking all of
; the task's children will cause the task to become unchecked", which is what
; made unticking the child also untick the parent on the ssh pair.
;
; THE PARENT KEEPS unchecked AND THE ssh PARENT DOES NOT, AND THAT IS THE
; RULING RATHER THAN AN INCONSISTENCY: 75 says an unticked API box means SD
; opens no socket at all, so the API defaults OFF; the ssh server defaults ON
; when the machine has none.
;
; AND THE CHILD'S GroupDescription IS GONE.  The ssh child carries none - the
; parent's heading covers the group - and a second copy on the child is what
; made this pair render unlike the one it was copied from.
;
; ***ONLY THE WIZARD CAN JUDGE THIS.  ISCC CHECKS THAT TASKS COMPILE, NOT THAT
; THEY BEHAVE*** - it passed the broken version - and no cycle or suite run ever
; sees this page.  cycle.ps1 -SkipInstall builds the installer without touching
; the tree; running the .exe to the tasks page and cancelling writes nothing.
; 02 Sep 26 - "Check: ApiConfAbsent", PRE_RELEASE_FIXES 89 Defect A, owner's
; ruling of 2 Sep 2026.  THE BOX COULD NOT OPEN A SOCKET ON A TREE THAT ALREADY
; HAD sd.conf, because the [Files] pair that writes it is onlyifdoesntexist on
; both arms - so on the uninstall-then-reinstall path it was offered, ticked,
; and inert.  Hidden now, the way sshserver hides on a machine that already has
; a server.  The subtask goes with it: a child cannot outlive its parent.
;
; ***AND THE FIREWALL CALL IS GATED IN THE SAME EDIT, WHICH IS THE HALF THAT
; MATTERS.***  ApplyApiFirewall follows ApiNetworkWanted, and a hidden task
; reads as NOT selected - so hiding this box alone would have CLOSED port 4243
; on every reinstall, turning "visible but inert" into "invisible but active".
; That is the trap ShouldSkipPage's own comment records, arriving by a second
; route.  The box and its firewall action now stand or fall together.
Name: "apiremote"; Description: "Provide the SD Core API (port 4243)"; \
    GroupDescription: "3)  SD Core API - Availability and Access:"; Flags: unchecked checkablealone; \
    Check: ApiConfAbsent
Name: "apiremote\apinetwork"; Description: "Let other computers on your network reach it"; \
    Flags: unchecked dontinheritcheck

[Files]
; --- C:\Program Files\SD\ --------------------------------------------------
; Everything here is program.  It is overwritten on upgrade and removed on
; uninstall, which is what should happen to program files.
;
; CORRECTED 25 Aug 2026, in place per the standing rule about wrong comments.
; This said "REPLACED on upgrade", and replaced is not what happens: Inno's
; [Files] copies and overwrites, and never removes a file that is ABSENT from
; the new version - which is the entire reason [InstallDelete] exists.  So a
; script dropped from stage.py sits here until somebody uninstalls SD.  The
; difference is invisible until the first time something is retired, which is
; why it went unnoticed.  stage.py's PF_RETIRED is the list that removes one,
; and assert-current section B4 is what notices a leftover in the first place.
Source: "{#Stage}\ProgramFiles\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

; --- THE ONE FILE THAT IS NEEDED BEFORE ANY FILE IS INSTALLED --------------
; 25 Aug 26 - ssh-preflight.ps1 decides whether SD may install here AT ALL, so
; InitializeSetup has to run it before the wizard is drawn and long before the
; line above has copied anything.  dontcopy embeds a second copy in the
; installer for ExtractTemporaryFile to unpack into {tmp}; it is NOT installed
; by this entry.
;
; THE {app} COPY ABOVE IS DELIBERATE AS WELL, not a duplicate by accident: it
; is what lets an administrator re-run the check by hand afterwards, the same
; way ssh-firewall.ps1 and allow-ssh-groups.ps1 can be re-run.  stage.py:598
; carries the same note from the other end.
;
; NAMED EXPLICITLY rather than swept up by a wildcard, because a wildcard here
; would silently embed every script in the staged tree in the installer twice
; and nobody would notice the size.
Source: "{#Stage}\ProgramFiles\ssh-preflight.ps1"; Flags: dontcopy

; 30 Aug 26 - AND ssh-firewall.ps1 FOR THE SAME REASON, PRE_RELEASE_FIXES 76.
; InitializeSetup asks it -ScopeFile for the CURRENT firewall scope, because
; that is the default state of the "allow remote access" checkbox and a [Tasks]
; Check is evaluated while the wizard is being built.  Same shape as the line
; above: a second embedded copy for ExtractTemporaryFile, with the {app} copy
; further up still the one an administrator re-runs by hand.
Source: "{#Stage}\ProgramFiles\ssh-firewall.ps1"; Flags: dontcopy

; --- C:\ProgramData\SD\ ----------------------------------------------------
; THE DATA TREE IS INSTALLED ONCE AND NEVER TOUCHED AGAIN.
;
; uninsneveruninstall, because this is the user's database.  Uninstalling SD
; must not remove accounts, passwords or data - the repository owner's
; instruction, 14 Aug 2026 - and the boundary between "shipped" and "the
; user's" runs through the middle of this tree: accounts ships with the SDSYS
; record in it and then accumulates every account the user creates.  There is
; no way to remove the shipped half without risking the other, so none of it
; is removed.  The opt-in path in [Code] deletes the whole tree instead, which
; is honest about what it is doing.
;
; The Check picks the branch rather than blocking one.  On a FIRST install
; this entry lays down the whole tree.  On a machine that already has
; C:\ProgramData\SD\sdsys it is skipped, and the generated upgrade.iss
; included below does the work instead - replacing the shipped half in place
; and leaving the user's half alone.
;
; CORRECTED 25 Aug 2026, in place rather than deleted, per the standing rule
; about wrong comments.  This paragraph used to end "UPGRADING AN EXISTING
; DATABASE IS NOT SOLVED - a new release's gpl.bp.out will not reach an
; existing install, and that needs a migration story before there is ever a
; second release."  That was true for eleven days and is the sentence a
; returning reader will remember, so it is kept next to what replaced it.
Source: "{#Stage}\ProgramData\sdsys\*"; DestDir: "{#DataDir}\sdsys"; \
    Flags: recursesubdirs createallsubdirs uninsneveruninstall; Check: DataTreeAbsent

; sd.conf is separate from the tree above because it needs BOTH flags:
; onlyifdoesntexist so a reinstall does not discard settings the user edited,
; and uninsneveruninstall so uninstalling does not delete their configuration.
; Without the second one Inno removes it like any other installed file, because
; unlike the database it genuinely is one.
;
; 25 Aug 26 - TWO SOURCES, ONE DESTINATION, chosen by the mode page.  A
; stand-alone install must open no port at all, and that is decided by sd.conf
; carrying no APIPORT - not by a firewall rule.  gplbld/stage.py derives the
; stand-alone file from SD_CONF by commenting out one line and REFUSES if that
; line is not found, so the pair cannot drift.
;
; THE Check: IS SAFE HERE IN A WAY IT WOULD NOT BE ON A [Tasks] ENTRY.  [Files]
; checks are evaluated during the install step, long after the wizard - the same
; timing DataTreeAbsent above has always relied on.
;
; ONE OF THE TWO ALWAYS FIRES AND NEVER BOTH: ApiWanted is a single Boolean and
; these are its two branches.  onlyifdoesntexist still applies to each, so
; neither overwrites a configuration the user has edited, and an upgrade
; rewrites nothing either way.
;
; 30 Aug 26 - RE-KEYED FROM StandaloneChosen TO THE API BOX.  PRE_RELEASE_FIXES
; 75.  The two files are unchanged and so is the mechanism; what changed is the
; question that picks between them.  sd-standalone.conf is SD_CONF with APIPORT
; commented out, and stage.py:499 records why that is the real switch rather
; than a firewall rule: "open_api_listener() returns -1 for 'no listener' when
; the port is <= 0".  So an unticked API box now means NO LISTENER, which is
; what the owner asked for - "the port should not be left open" - rather than a
; listener with a closed port in front of it.
;
; ***THE FILE NAME IS NOW WRONG AND IS DELIBERATELY NOT RENAMED.***  There is no
; stand-alone mode any more, but sd-standalone.conf is generated by stage.py and
; renaming it would touch the staging script, the upgrade branch and this entry
; for no behavioural gain, in the same change that already moves the meaning.
; stage.py's own comment now says what it is: the no-listener configuration.
Source: "{#Stage}\ProgramData\sd.conf"; DestDir: "{#DataDir}"; \
    Flags: onlyifdoesntexist uninsneveruninstall; Check: ApiWanted
Source: "{#Stage}\ProgramData\sd-standalone.conf"; DestDir: "{#DataDir}"; \
    DestName: "sd.conf"; \
    Flags: onlyifdoesntexist uninsneveruninstall; Check: not ApiWanted

; --- THE UPGRADE BRANCH, GENERATED --------------------------------------------
; 25 Aug 26.  gplbld/stage.py writes <stage>\upgrade.iss from SDSYS_SHIP +
; SDSYS_EMPTY + the terminfo pair, minus SDSYS_PRESERVE, and it carries its own
; [InstallDelete] and [Files] sections gated on Check: DataTreeUpgrade.  Read
; that file's header for the rule; read stage.py's SDSYS_PRESERVE for what an
; upgrade must never touch and why.
;
; IT IS INCLUDED RATHER THAN WRITTEN HERE BECAUSE A COPY WOULD GO STALE
; SILENTLY, and the thing it would go stale about is which directories an
; upgrade DELETES from a live database.  Same reasoning as the MSYS2 DLL
; closure being computed instead of listed.
;
; A MISSING FILE IS A BUILD FAILURE, DELIBERATELY.  #include stops ISCC if the
; file is not there, and a tree staged without --bootstrap gets an upgrade.iss
; whose only content is #error.  Both are loud.  The quiet failure this avoids
; is an installer that builds cleanly and then cannot upgrade anything.
;
; THIS LINE MUST STAY LAST IN [Files], AND IT MUST NOT MOVE BELOW [Code].  The
; include opens [InstallDelete], so any Source: entry put after it lands in the
; wrong section - and inside [Code] the generated file's own ";" header
; comments stop being comments and are compiled as Pascal, which answers
; "'BEGIN' expected" on line 1 of a file that has no Pascal in it at all.
; Both measured 25 Aug 2026 against the real ISCC, the second one by doing it.
;
; PASS AN ABSOLUTE /DStage.  cycle.ps1 does - it is C:\Users\dmont\stagetest by
; default - and it is the only supported way to build.  ISPP resolves a
; RELATIVE #include against the directory holding THIS file, gplbld\, while
; ISCC resolves a relative Source: against SourceDir; the two are not the same
; directory, so a relative /DStage would send them to different places.  It
; fails loudly either way, naming the file it could not open.
#include AddBackslash(Stage) + "upgrade.iss"

[Dirs]
; Created empty and left alone.  shm is where etc\fstab maps /dev/shm, so every
; SD user needs to be able to write in it; the ACLs below grant that.
Name: "{#DataDir}\user_accounts"; Flags: uninsneveruninstall
Name: "{#DataDir}\group_accounts"; Flags: uninsneveruninstall
Name: "{#DataDir}\shm"; Flags: uninsneveruninstall

; 02 Sep 26 - PRE_RELEASE_FIXES 120.  THE THREE SDSYS DIRECTORIES THAT SHIP
; EMPTY, AND WHY BEING EMPTY IS THE WHOLE DEFECT.
;
; stage.py creates sdsys\bp, sdsys\bp.out and sdsys\batch.jobs EMPTY and puts
; all three on the PRESERVED list - "the directory still has to exist", because
; voc_template\bp is an F-pointer at it and secure-sysdirs.ps1 hardens it.
;
; ***uninsneveruninstall ON THE [Files] TREE PROTECTS FILES, NOT AN EMPTY
; DIRECTORY.***  On a normal site nobody has written a BASIC program or
; scheduled a batch job, so these three hold nothing at uninstall time and the
; uninstaller takes the directories - while sdsys\accounts, which has content,
; survives.  That asymmetry is exactly what was measured on guest Test 1: the
; store gone and batch.jobs.dic still present and correctly locked.
;
; ***AND THE REINSTALL COULD NOT PUT THEM BACK***, which is what made it a
; blocker rather than a blemish: the data tree is present so DataTreeAbsent is
; false, the whole-tree [Files] entry does not fire, and upgrade.iss replaces
; only SHIPPED files - these are preserved either way.  So the site stayed
; unhardened for ever and was told so on every later install, while the remedy
; the closing box printed named the very paths that did not exist and exited 2
; as well.
;
; A [Dirs] entry fixes both halves at once and is why this is three lines
; rather than new code: it carries NO Check:, so it runs on every install and
; HEALS a tree that already lost them, and uninsneveruninstall stops the
; uninstaller taking them again.
;
; bp.out IS HERE THOUGH 120 DID NOT NAME IT, AND THAT IS DELIBERATE.  It is the
; same class - created empty, preserved, same disappearance - but NOTHING
; HARDENS IT, so its loss is reported by nobody.  A silent sibling of a defect
; that at least announced itself is the more dangerous of the two, not the
; less, and leaving it would be fixing the instance instead of the class.
Name: "{#DataDir}\sdsys\bp"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\bp.out"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\batch.jobs"; Flags: uninsneveruninstall

; 02 Sep 26 - PRE_RELEASE_FIXES 132.  THE OTHER THREE, FOUND BY MEASURING THE
; FIX ABOVE RATHER THAN BY ANOTHER SITE LOSING THEM.
;
; The witness run for 120 swept every SDSYS_PRESERVE directory instead of only
; the three it had just fixed, and found cat, prt and $hold gone by the same
; mechanism on the same install.  ONLY cat SAID SO: secure-sysdirs.ps1 hardens
; it, so its absence reached the closing box as "An SD Core system directory
; was NOT locked (code 2)"; nothing hardens prt or $hold, so those two vanished
; in silence.  That is the bp.out argument above, and it now has evidence
; instead of foresight.
;
; ***WHAT MAKES THIS WORSE THAN THREE MISSING DIRECTORIES IS THAT THE INSTALLER
; PROMISES THEM BY NAME.***  The upgrade notice at the MsgBox below tells the
; reader "YOUR DATA IS UNTOUCHED: ... anything you catalogued, the print queue,
; held output ..." - cat, prt and $hold, three of its six named promises - and
; that sentence is generated from stage.py's SDSYS_PRESERVE while the
; protection was enumerated here by hand.  The promise tracked a ten-entry list
; and the machine tracked a three-entry one.
;
; ***dumps IS NOT HERE, AND THAT IS A DECISION RATHER THAN AN OVERSIGHT.***  It
; is in the same class and does NOT disappear, because secure-dumps.ps1 creates
; it when absent and its [Run] entry carries no Check: - so it is repaired on
; every install by a second mechanism.  test-dirscoverage-units.ps1 knows that,
; declares it as the one exemption, and FAILS if the reason stops being true.
; Two mechanisms doing one job is what let this drift twice; the guard is what
; stops a third time.
Name: "{#DataDir}\sdsys\cat"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\prt"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\$hold"; Flags: uninsneveruninstall

; 02 Sep 26 - AND THE LAST FOUR, ON THE OWNER'S RULING THE SAME DAY: "as long
; as the directories are not needed and reinstalled when the install after
; removal happens".
;
; These four are in SDSYS_EMPTY and SDSYS_PRESERVE like the six above, and they
; survive a reinstall today - but only because the install happens to write
; records into them: $cred gets a credential from the adopt step, os.users gets
; the installing user, and WRITE_INSTALL_DICTS fills the two dictionaries.
; Measured on the 2 Sep 16:13 install: 1, 1, 5 and 3 entries.
;
; ***THAT IS NOT WHAT THE RULING ASKS FOR, WHICH IS WHY THEY ARE HERE RATHER
; THAN EXEMPT.***  Having content means the uninstaller does not TAKE the
; directory; it does not mean anything REINSTALLS it.  A site whose $cred or
; os.users happened to be empty at uninstall time would lose it exactly as cat,
; prt and $hold were lost, and no later install would put it back - the whole
; shape of 120.  A [Dirs] entry is the only one of the two mechanisms that
; heals, and it costs one line.
;
; NOTHING NEEDS THEM ABSENT.  A [Dirs] entry only ever creates, and both
; secure-cred.ps1 and secure-osusers.ps1 exit 2 when their path is missing - so
; guaranteeing existence can only move those from a failure to a success.
;
; AND THE UNINSTALL'S "remove the database" IS UNAFFECTED, checked rather than
; assumed: that path is DelTree(DataPath, True, True, True) in [Code], which
; deletes the tree outright and never consults the uninstall log, so
; uninsneveruninstall cannot keep anything the user asked to destroy.
Name: "{#DataDir}\sdsys\$cred"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\os.users"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\os.users.dic"; Flags: uninsneveruninstall
Name: "{#DataDir}\sdsys\batch.jobs.dic"; Flags: uninsneveruninstall

[Icons]
Name: "{group}\SD"; Filename: "{app}\usr\bin\sd.exe"; WorkingDir: "{#DataDir}"

; 22 Aug 26 - THE CHECK NEEDS TO BE FINDABLE, AND THAT IS NOT A CONVENIENCE.
; check-install.ps1 is offered as a tickbox at the end of the install, but the
; run it does there is ALWAYS the incomplete one: the installing user's token
; cannot carry sdusers until they sign out and back in, so every database check
; reports "not yet" by design.  The run that actually checks the database is
; the one AFTERWARDS - so without this shortcut the check could never be
; completed by anybody who did not write the command down.
;
; NOT ELEVATED, DELIBERATELY.  The question is whether this user's ORDINARY
; sign-in can reach SD; an administrator token reads the data tree through the
; Administrators ACE and would pass regardless.  The script detects elevation
; and says what the answer is worth, but that is the backstop, not the intent.
Name: "{group}\Check the SD Core installation"; \
    Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\check-install.ps1"""; \
    WorkingDir: "{app}"; \
    Comment: "Check that SD Core is installed and working. It only looks; it changes nothing."

[Run]
; ORDER MATTERS.  The group has to exist before icacls can grant to it, and the
; ACLs have to be right before anyone is invited in.

; sdusers is the group SD's own account provisioning uses - CREATE.ACCOUNT adds
; each new Windows user to it (PROJECT_STATUS.md 5.6).  Creating it here means
; a fresh machine can create accounts without a manual step.  Failure is not
; fatal: it already existing is the common case on a reinstall.
;
; NOTE IT IS NOT THE ADMINISTRATOR GROUP, and never was.  This grants access to
; the FILES; who administers SD is Windows Administrators (5.6.1).  The two are
; separate questions and it is worth not confusing them: an administrator who
; has not elevated does not carry Administrators in their token either, so they
; need sdusers to reach the data tree just as an ordinary user does.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdusers /add /comment:""SD users"""; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Creating the sdusers group..."

; AND PUT THE INSTALLING USER IN IT.  Without this, the icacls below locks the
; person who just installed SD out of their own database: the ACL grants
; SYSTEM, Administrators and sdusers, and an ordinary session carries a
; UAC-filtered token whose Administrators membership is "deny only" - so it
; matches none of the three.  SD would install perfectly and then fail to open
; anything, which is about the worst first impression available.
;
; This does NOT take effect in the session that runs the installer.  Windows
; fixes group membership in the access token at logon, so it stays invisible
; until the user signs out and back in.  That is the trap in
; PROJECT_STATUS.md 6, and it is why the wizard says so at the end.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdusers ""{username}"" /add"; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Adding {username} to sdusers..."

; sdsshonly is the group that confines an account to ssh (PROJECT_STATUS.md
; 5.6.2).  CREATE.ACCOUNT puts every NON-administrator account it creates into
; it; the deny rights below are what the membership actually means.
;
; IT IS DELIBERATELY NOT sdusers.  That grants access to the data files and
; administrators are in it too, so denying console logon there would lock the
; machine's administrators out of their own console.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdsshonly /add /comment:""SD accounts restricted to ssh"""; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Creating the sdsshonly group..."

; AND THIS IS WHAT MAKES THAT GROUP MEAN ANYTHING.  Applied ONCE, here, rather
; than per account: Windows has no cmdlet for user rights assignment, so doing
; it per account would need an LsaAddAccountRights P/Invoke or a secedit
; rewrite on every account creation.
;
; TWO RIGHTS, AND DELIBERATELY NOT A THIRD.  SeDenyInteractiveLogonRight blocks
; the console and SeDenyRemoteInteractiveLogonRight blocks Remote Desktop.
; SeDenyNetworkLogonRight IS NOT SET AND MUST NOT BE: Win32-OpenSSH
; authenticates with a network logon - cleartext network for passwords, S4U for
; keys - so denying it would remove the one route this is meant to preserve.
;
; LsaAddAccountRights rather than secedit, because secedit is a read-modify-
; write of the ENTIRE USER_RIGHTS area: it would rewrite unrelated machine
; policy and race anything else editing it.  This adds one right to one SID.
; Both calls are idempotent - adding a right an account already holds succeeds.
;
; Failure is not fatal, on the same reasoning as the ssh install: a machine
; where this cannot be applied should still get a working SD, with the
; restriction absent rather than the install broken.
;
; CORRECTED 16 Aug 2026, AND IT IS STILL A LOOSE END.  This comment used to
; claim the step "is checked at the end by CurStepChanged so it cannot fail
; silently, which is the mistake the OpenSSH step made".  IT IS NOT CHECKED -
; CurStepChanged never read it, and the mistake it names as somebody else's was
; being made here too.  Corrected in place rather than deleted, per the standing
; rule about wrong comments.
;
; NOT FIXED IN THE SAME PASS, deliberately, because it is not the ssh work and
; the fix is not a comment: unlike the OpenSSH step there is no machine state
; Inno can read to tell whether the rights were applied - user rights
; assignment needs LsaEnumerateAccountRights, so judging it means shelling out
; to a script the way ApplyAllowGroups does.  Recorded in PROJECT_STATUS.md 7
; step 3 rather than left here.
;
; What it costs while it stays unchecked: an account confined to sdsshonly on a
; machine where the deny rights never landed is NOT confined at all, and the
; install says nothing.  That is a quiet weakening, not a broken install, which
; is why it can wait - but it is exactly the shape of the six defects of
; 16 Aug 2026, each of which sat at a seam between two halves that were correct
; alone.
; CLOSED 17 Aug 2026: THE STEP MOVED TO THE CODE SECTION, as ApplyDenyLogon,
; called at ssPostInstall.  The loose end the comment above records was that a
; Run entry discards the exit code, so the one thing this step could not do was
; report having failed - and a group that is not actually denied the console is
; a quiet weakening nobody would notice.  The reasoning is on that function.

; THIS IS THE STEP THAT MAKES THE DATA PRIVATE.  Nothing SD does at runtime
; substitutes for it.  C:\ProgramData grants BUILTIN\Users:(I)(OI)(CI)(RX) by
; inheritance, so without this the whole database is world readable and
; snooping needs no privilege at all.
;
; /inheritance:r FIRST and in the same command - /grant alone leaves the
; inherited Users:(RX) in place and the tree stays readable.
;
; SIDs, not names: *S-1-5-18 is SYSTEM and *S-1-5-32-544 is
; BUILTIN\Administrators, and both are renamed on a localised Windows.
; sdusers is our own name, so it is safe to write out.
;
; Everything created underneath inherits this afterwards, including files SD
; writes through the MSYS2 runtime - NTFS applies inheritance in the kernel, so
; it works even though the mount is noacl and chmod is a no-op.  That is what
; makes one icacls enough.  See PROJECT_STATUS.md 5.7.
Filename: "{sys}\icacls.exe"; \
    Parameters: """{#DataDir}"" /inheritance:r /grant ""*S-1-5-18:(OI)(CI)F"" /grant ""*S-1-5-32-544:(OI)(CI)F"" /grant ""sdusers:(OI)(CI)M"""; \
    Flags: runhidden; StatusMsg: "Securing the data directory..."

; AND THEN TAKE MOST OF THAT BACK ON ONE FILE.  The grant above is what every
; SD user needs to use the database; inherited onto the audit trail it would
; also let them read, rewrite and delete the record of what they did.  This
; step breaks inheritance on that one file and leaves sdusers with AppendData
; and nothing else - measured 16 Aug 2026: appending works, reading,
; truncating, overwriting, renaming and deleting are all refused.
;
; IT MUST COME AFTER THE icacls ABOVE.  Run it before and inheritance puts the
; directory's Modify straight back on the file.
;
; A SHIPPED SCRIPT RATHER THAN AN INLINE COMMAND, for the reason the OpenSSH
; entry below gives at length: an inline parameter is where a brace bug hid for
; its whole life, and a file can be parse-checked on its own.
;
; No exit code check here, deliberately.  secure-audit.ps1 never truncates an
; existing trail and SD falls back to creating the file itself if this step did
; not run - the trail is then inherited-Modify rather than append-only, which
; is the pre-16-Aug behaviour and not a broken install.  PROJECT_STATUS.md 7
; step 4 names this as the thing to check if a trail turns out to be editable.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-audit.ps1"" -Path ""{#DataDir}\sdsys\audit"""; \
    Flags: runhidden; StatusMsg: "Making the audit trail append-only..."

; 02 Sep 26 - PRE_RELEASE_FIXES.md 28.  AFTER the tree ACL for the same reason
; as secure-audit.ps1 above: inheritance would otherwise put sdusers Modify back
; on the directory, which is the whole defect - a process dump carries the
; variable state of the session that wrote it, and sdsys is readable by every
; SD user.  stage.py's SD_CONF points DUMPDIR here; without that, pdump.c:98
; falls back to sysdir and this directory is never used.
;
; No exit code check, on secure-audit.ps1's precedent: if this step does not
; run, dumps land in a directory that is inherited-Modify rather than
; write-only, which is the pre-28 behaviour and not a broken install.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-dumps.ps1"" -Path ""{#DataDir}\sdsys\dumps"""; \
    Flags: runhidden; StatusMsg: "Securing the process-dump directory..."

; THE CREDENTIAL STORE IS NOT LOCKED HERE.  It is locked from the Code section,
; by SecureCredStore, called at ssPostInstall.  MOVED OUT OF THIS SECTION
; 17 Aug 2026 because a Run entry discards the exit code, and this is the one
; step whose silent failure is a privilege escalation rather than a degraded
; install.  The reasoning, and what the entry here got wrong for its whole
; life, are on that function.

; THE ELEVATION HELPER'S LOG, and it must exist before the helper ever runs.
; sd-elevate.ps1 logs only if this file is already there, precisely so that a
; missing one means "no logging" rather than "a log created with the data
; tree's Modify for every SD user" - see the note at the top of that script.
;
; SAME ORDERING RULE AS THE AUDIT TRAIL ABOVE: after the icacls, never before.
;
; NOT IN sdsys, and not in the user's AppData either.  sdsys is the database;
; the operational logs an administrator goes looking for - sdsvc.log,
; adopt-account.log - live here.  AppData was considered and rejected on
; 16 Aug 2026: the user owns their own profile, so the person the log is about
; could reset its ACL and rewrite it.  secure-log.ps1's header has the full
; reasoning.
;
; No exit code check, as above.  If this step does not run, sd-elevate.ps1
; finds no file and logs nothing, which is exactly the pre-16-Aug behaviour.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-log.ps1"" -Path ""{#DataDir}\sd-elevate.log"""; \
    Flags: runhidden; StatusMsg: "Securing the elevation log..."

; WHERE !ps_script PUTS A SCRIPT THAT MAY CARRY A PASSWORD.  It used to write
; them into the account directory, which the grant above leaves writable by
; every SD user - so one user could read another's new Windows password, and,
; worse, rewrite a pending script before the elevated helper ran it.  This
; creates SDSYS\pstmp with a per-creator ACL; secure-psdir.ps1 has the detail.
;
; ORDER: after the icacls, as above, AND BEFORE adopt-account.ps1, which runs
; at ssPostInstall and is the install's own first caller of !ps_script.  [Run]
; finishes before ssPostInstall, so being in this section is enough.
;
; NOT A [Dirs] ENTRY, deliberately.  Creating anything under {#DataDir}\sdsys
; before [Files] runs risks the installer's own "a database is already here"
; test seeing a directory it did not put there - PROJECT_STATUS.md section 6.
; The script creates it, which keeps that test looking at an untouched tree.
;
; !ps_script FAILS CLOSED if this directory is absent, so a failure here stops
; account creation rather than quietly writing privileged scripts somewhere
; every SD user can edit them.  That is the intended trade.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-psdir.ps1"" -Path ""{#DataDir}\sdsys\pstmp"""; \
    Flags: runhidden; StatusMsg: "Securing the script directory..."

; WHERE DELETE_USER RECORDS A PROFILE IT COULD NOT REMOVE.  28 Aug 26,
; PRE_RELEASE_FIXES.md 36.  A Windows profile cannot be deleted while its
; registry hive is still mounted, so gpl.bp/DELETE_USER keeps both halves of
; the profile and writes a record here; sdsvc.exe runs reclaim-profiles.ps1 at
; every service start - which is every boot, as LocalSystem - and that is when
; the pair finally goes.
;
; SAME REASON AS THE ENTRY ABOVE, AND IT IS THE SERIOUS HALF AGAIN.  The
; icacls that secures the data tree grants sdusers:(OI)(CI)M to everything
; underneath.  Left to inherit, this store would be A LIST OF DIRECTORIES
; EVERY SD USER CAN EDIT AND LocalSystem LATER DELETES.  secure-reclaim.ps1
; breaks inheritance and grants SYSTEM and Administrators only.
;
; ORDER: after the icacls, as above, or inheritance puts the Modify back.
;
; WHY IT IS DONE HERE AND NOT LEFT TO DELETE_USER, which creates the directory
; with the same ACL if it is missing: the parent is writable by every SD user,
; so one of them could create this directory FIRST and own it, and
; DELETE_USER's "create it if absent" would then find it already there and
; leave their ACL alone.  Creating it during the install closes that window.
; The sweep re-asserts the ACL at every boot as the third line of defence, and
; refuses any record file not owned by SYSTEM or Administrators.
;
; A FAILURE HERE IS NOT FATAL and the exit code is not checked: no store means
; DELETE_USER reports status 8 - "left behind and nothing is coming back for
; it" - which is a warning with instructions, not a broken install.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-reclaim.ps1"" -Path ""{#DataDir}\profile-reclaim"""; \
    Flags: runhidden; StatusMsg: "Securing the profile reclaim store..."

; OPT-IN AND DEFAULT OFF SINCE 1 Sep 2026 - see the note in [Tasks].  The Check
; is SshServerWanted (the ticked box, which only appears when this machine has
; none), so a server is installed only when the user asks for one and one that
; already exists is never touched.
;
; A FAILURE HERE - OR THE BOX SIMPLY LEFT UNTICKED, WHICH IS NOW THE DEFAULT -
; MUST NOT FAIL THE SD INSTALL.  Installing is a Features on Demand download, and
; policy, a WSUS with no FoD source, a metered connection or an offline machine
; can each block it (5.9); and by default the user has not asked for it at all.
; Either way the machine lands in an SD with no ssh server, in which NO ACCOUNT
; BUT THE INSTALLING USER'S CAN SIGN IN ANYWHERE.  That is now the DEFAULT rather
; than an edge case, and it is not silent: SshReport says so at the end.
;
; MOVED OUT OF THIS FILE ON PURPOSE - see install-ssh.ps1.  It used to be an
; inline -Command, and it carried a brace bug for its entire life: Inno escapes
; a literal "{" as "{{" but needs no escape for "}", so "}}" reached PowerShell
; as two closing braces and the whole script was a syntax error before it ran.
; Ticking the box installed nothing and, because this entry deliberately checks
; no exit code, said nothing either.  A shipped file can be read and
; parse-checked on its own; an inline parameter cannot.
;
; IT STAYS A [Run] ENTRY RATHER THAN MOVING TO [Code] WITH THE OTHERS, and the
; reason is the StatusMsg.  This step hands off to TiWorker and can work for
; minutes with nothing on screen; it was reported as a hang during testing on
; 14 Aug 2026, when it was optional and rare.  It is now on every install of a
; machine without ssh, so the one line saying what it is doing matters more than
; the exit code does - and the exit code is not what is judged anyway.
;
; CORRECTED 16 Aug 2026.  This comment used to end "Exit 2 means installed,
; restart required, which CurStepChanged reports."  IT DID NOT.  Nothing read
; this entry's exit code at all - a [Run] entry discards it - and CurStepChanged
; handled only ApplyAllowGroups and AdoptAccount.  The claim is left visible
; rather than deleted because it is the second comment in this file found
; asserting a check that was never written.  What replaces it is better than the
; exit code would have been: SshReport reads the MACHINE STATE afterwards, which
; also answers correctly when the capability was already installed.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-ssh.ps1"""; \
    Flags: runhidden skipifdoesntexist; Check: SshServerWanted and not TrueUpgrade; \
    StatusMsg: "Installing OpenSSH Server (this can take several minutes)..."
; 30 Aug 26 - THE GATE IS THE BOX NOW, NOT THE MACHINE.  PRE_RELEASE_FIXES 67.
; It used to read "SshServerAbsent and not StandaloneChosen", which is the whole
; of the defect that entry recorded: the reader could leave every ssh box blank
; and still get the capability installed, sshd started and sshd_config rewritten,
; because this line never tested a box at all.  SshServerWanted IS the box, and
; it can only be true when the server was absent - that is its own Check.

; THE FULL-SCREEN EDITORS, 26 Aug 2026, and this is not a task either.  There
; are two verbs and two editors: EDIT runs Microsoft Edit, which ships IN
; Windows on current builds, and MICRO runs micro, which is always a winget
; install.  install-editors.ps1 checks for each before reaching for winget.
; Offering them as a checkbox would mean a programmer account with a verb that
; does nothing on a machine where somebody unticked a box months earlier.
;
; IT RUNS ON A STAND-ALONE INSTALLATION TOO, unlike the ssh line above.  A
; stand-alone install is the one person at one computer writing code, which is
; exactly who wants an editor.
;
; ITS EXIT CODE IS NOT READ, AND THAT IS DELIBERATE RATHER THAN THE OVERSIGHT
; THE SSH ENTRY ABOVE RECORDS.  There is no state to check afterwards that the
; script has not already checked, and no outcome that should stop an install:
; exit 2 means SD is complete and one editor verb is not.  What replaces the
; exit code is the script's own log, C:\ProgramData\SD\install-editors.log,
; written because a runhidden step that prints has said nothing.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-editors.ps1"""; \
    Flags: runhidden skipifdoesntexist; \
    StatusMsg: "Checking for the full-screen editors..."

; THE SERVICE, AND IT IS NOT A TASK - owner's decision, 15 Aug 2026.  SD must
; be running when the installer finishes and after every Windows startup, so
; this is not offered, it is done.  Until now there was no service at all and
; "sd -start" had to be typed after every restart.
;
; BEFORE the account step in [Code], which is why it is here rather than at
; ssPostInstall: adopt-account.ps1 starts SD itself if it has to, and having
; the service already running means it does not have to - one less thing to
; race, and that race cost an install earlier the same day.
;
; No Tasks: condition and no Check:.  A shipped .ps1 rather than inline sc.exe
; for the reason above the ssh entry - sc.exe binPath quoting inside an Inno
; parameter is exactly the sort of thing that silently produces a broken
; service, and a shipped file can be read and parse-checked on its own.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-service.ps1"" -Install -AppDir ""{app}"""; \
    Flags: runhidden skipifdoesntexist; \
    StatusMsg: "Creating and starting the SD service..."

; THE POST-INSTALL CHECK IS NOT A [Run] ENTRY AT ALL ANY MORE - 22 Aug 2026.
; It was a "postinstall" tickbox here, and the owner met two faults with that on
; a real install:
;
;   * TWO YES/NO QUESTIONS for one action - the tickbox on the Finished page and
;     then the script asking again.  The script's question is the one that gets
;     read, so the tickbox was the one to go.
;   * It ran while the wizard was still on screen, so the install window sat
;     open behind it.
;
; Both are now answered by finish-install.ps1, launched from DeinitializeSetup
; once the wizard has gone - see RunFinishingStep and DeinitializeSetup in
; the Code section.  It runs the password step and the check IN ORDER, in ONE
; window, and Setup is not waiting on either.

; THERE IS DELIBERATELY NO "SET THE SDSYS PASSWORD" STEP.
;
; Removed 14 Aug 2026 with the decision that a Windows administrator IS an SD
; administrator (PROJECT_STATUS.md 5.6.1).  Whoever runs this installer is an
; administrator - Inno requires it - so they already administer SD when it
; finishes, and there is nothing they must set to get in.  Accounts still carry
; passwords; what changed is that the SDSYS password is no longer what confers
; administration, so demanding one at install time asks for a credential that
; secures nothing the installer has not already granted.
;
; It was also broken two ways over, which is how the decision came up.  Measured
; on a real interactive install, 14 Aug 2026:
;
;   1. sd -internal needs a running server and the installer never runs
;      sd -start, so it failed with "SD has not been started".
;   2. Inno logs the entry as "Run as: Original user", so it ran with the
;      UNELEVATED token - which does not carry sdusers until the user signs out
;      and back in, so it could not have opened the database either.
;
; And "nowait" meant the console vanished before either message could be read,
; so it looked to the user as though nothing had happened at all.  If a password
; step is ever wanted back, all three have to be fixed together.

[UninstallRun]
; THE SERVICE GOES FIRST, and the order is load-bearing.  Removing it stops it,
; which stops SD; doing it the other way round lets the service notice the
; daemon has gone and, with the restart action configured, start it again from
; files that are being deleted underneath it.
;
; It is also why this is not left to "sd -stop" alone below - that would end
; the daemon while leaving a service pointing at an executable about to vanish,
; which is how a machine ends up with a permanently failing service after an
; uninstall.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-service.ps1"" -Remove"; \
    Flags: runhidden skipifdoesntexist; RunOnceId: "RemoveSDService"

; Stop the server before removing the files it is running from.  Ignore any
; failure: not running is the normal case, and after the service has gone it
; is the usual one.
Filename: "{app}\usr\bin\sd.exe"; Parameters: "-stop"; Flags: runhidden; \
    RunOnceId: "StopSD"

[Code]

{ ---------------------------------------------------------------------------
  Detection helpers
  --------------------------------------------------------------------------- }

var
  DataTreeWasAbsent: Boolean;
  SshWasAbsent: Boolean;
  { 31 Aug 26 - PRE_RELEASE_FIXES 88.  Was SD ALREADY INSTALLED when we
    arrived - not merely "is there a data tree"?

    ***IT MUST BE SAMPLED ONCE, LIKE THE TWO ABOVE, AND FOR A SHARPER REASON:
    THE INSTALLER WRITES THIS KEY ITSELF.***  Inno creates the uninstall entry
    at the END of the install, so a live query later in the same run would
    start answering TRUE and the wizard would contradict itself.  Read in
    InitializeSetup, before anything is written.

    WHY IT IS NOT DataTreeUpgrade.  That asks about C:\ProgramData\SD\sdsys,
    which the UNINSTALLER DELIBERATELY KEEPS - so uninstall-then-install looks
    identical to an upgrade by that test, while the uninstaller has already
    torn down RemoveAllowGroups, RemoveApiFirewall and RemoveFromPath.  Skipping
    the tasks page there would leave the reader no way to put any of it back and
    never ask.  The uninstall key is the discriminator: the uninstaller removes
    it, so present means SD is genuinely installed right now. }
  SdWasInstalled: Boolean;
  { 30 Aug 26 - PRE_RELEASE_FIXES 76.  Was the EXISTING ssh server's firewall
    rule already open to the network when we arrived?  Sampled once in
    InitializeSetup, for the same reason as the two above and for one more of
    its own: it is the DEFAULT STATE of a checkbox, and a [Tasks] Check is
    evaluated while the wizard is being built, so it has to be a plain Boolean
    by then and not a shell-out.

    ONLY MEANINGFUL WHEN SshWasAbsent IS FALSE.  When SD installs the server
    itself the rule does not exist yet, and install-ssh.ps1 creates it open -
    which is why the absent case defaults its box UNCHECKED and this one does
    not.  Left False in that case and never read; the [Tasks] Checks that use
    it all carry "not SshServerAbsent" first. }
  SshRuleWasOpen: Boolean;
  { 29 Aug 26 - PRE_RELEASE_FIXES 39.  Where the account sweep was stashed at
    usUninstall, or empty if it could not be.  It has to be COPIED out of the
    application directory before that directory is deleted: the sweep is
    offered at usPostUninstall, to follow the database question the owner's
    ruling says it follows, and by then everything under the app directory has
    gone - which is the same reason RemoveAllowGroups runs at usUninstall
    instead.  Empty means "do not offer it", so a failed copy costs the prompt
    rather than producing one whose Yes cannot do anything. }
  SdAccountsScript: String;
  { 30 Aug 26 - StandaloneWasMarked IS GONE WITH THE MODE IT RECORDED.
    PRE_RELEASE_FIXES 75.  Nothing reads the '$standalone' marker any more. }
  { 22 Aug 26 - THE FINISHING STEP RUNS AFTER THE WIZARD HAS GONE, so what it
    needs to know has to outlive the procedure that learns it.  Both are set at
    ssPostInstall and read in DeinitializeSetup.

    InstallReachedPostInstall IS A GUARD, NOT A CONVENIENCE.  DeinitializeSetup
    is called however Setup ends, cancelling included; without this, cancelling
    on the first page would still open an SD session on a machine that has just
    had nothing installed.

    PasswordStepWanted is false on the reinstall case (adopt code 2), where the
    account was left alone and keeps whatever password it had.  There is then
    nothing to ask for, and finish-install.ps1 says so rather than leaving a
    reader wondering what became of the step it promised them. }
  InstallReachedPostInstall: Boolean;
  PasswordStepWanted: Boolean;

{ 30 Aug 26 - IS THE EXISTING ssh SERVER'S FIREWALL RULE ALREADY OPEN TO THE
  NETWORK?  PRE_RELEASE_FIXES 76.  Called once from InitializeSetup, and only
  when a server was already here; the answer becomes the default state of the
  "allow remote access" checkbox, so that leaving the box alone changes nothing.

  ***EVERY FAILURE PATH ANSWERS False, AND THAT IS THE SAFE DIRECTION.***  The
  box this feeds OPENS a port when ticked, so "we could not find out" must not
  pre-tick it.  There are four ways to get nothing - the extract fails, the
  script will not start, it exits non-zero, or the file it should have written
  is missing or says something else - and all four land on False.

  IT IS READ-ONLY.  -ScopeFile carries no -Installed gate because reading the
  scope of a server SD did not install is not reconfiguring it (5.9). }
function GetSshRuleIsOpen: Boolean;
var
  Ps, ScriptPath, ScopePath: String;
  Scope: AnsiString;
  Code: Integer;
begin
  Result := False;

  ExtractTemporaryFile('ssh-firewall.ps1');
  Ps         := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ScriptPath := ExpandConstant('{tmp}\ssh-firewall.ps1');
  ScopePath  := ExpandConstant('{tmp}\ssh-firewall-scope.txt');

  if not Exec(Ps,
              '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
              ScriptPath + '" -ScopeFile "' + ScopePath + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Log('SD: ssh-firewall.ps1 -ScopeFile could not be started; ' +
        'the remote-ssh box defaults to unticked.');
    Exit;
  end;

  if Code <> 0 then
  begin
    Log('SD: ssh-firewall.ps1 -ScopeFile exited ' + IntToStr(Code) +
        '; the remote-ssh box defaults to unticked.');
    Exit;
  end;

  if not FileExists(ScopePath) then
  begin
    Log('SD: ssh-firewall.ps1 -ScopeFile wrote no file; ' +
        'the remote-ssh box defaults to unticked.');
    Exit;
  end;

  Scope := '';
  LoadStringFromFile(ScopePath, Scope);

  { MATCHED ON THE POSITIVE WORD ONLY.  "restricted" CONTAINS neither "open"
    nor anything else this tests, so there is no wording shared by the two
    answers - the trap CLAUDE.md's "anchor on the SUCCESS wording" section is
    about.  Anything unrecognised is False. }
  Result := (Trim(String(Scope)) = 'open');
  if Result then
    Log('SD: existing ssh firewall scope read as "' + Trim(String(Scope)) +
        '"; the remote-ssh box starts TICKED, so leaving it alone keeps the ' +
        'exposure this machine already had.')
  else
    Log('SD: existing ssh firewall scope read as "' + Trim(String(Scope)) +
        '"; the remote-ssh box starts unticked.');
end;

function InitializeSetup: Boolean;
var
  PreflightPs, PreflightScript, PreflightReasonPath: String;
  PreflightReason: AnsiString;
  PreflightCode: Integer;
begin
  (* ASKED ONCE, BEFORE ANY FILE IS COPIED, AND THE ANSWER CACHED.

     A Check function is evaluated PER FILE.  When this tested DirExists
     directly, the first file of the sdsys set created the directory, every
     later evaluation therefore answered False, and the remaining ~3,260 files
     were silently skipped - producing an install whose database contained 16
     files and no catalogue at all.  Setup still exited 0.

     It survived the first round of testing because the upgrade case skips the
     whole set consistently and so looks identical either way.  Only a genuine
     first install exposes it.  Measured 14 Aug 2026. *)
  DataTreeWasAbsent := not DirExists(ExpandConstant('{#DataDir}\sdsys'));

  (* 31 Aug 26 - IS SD INSTALLED RIGHT NOW?  PRE_RELEASE_FIXES 88.  Sampled
     here and never again, because Inno writes this very key at the end of the
     install - see the variable's own comment.

     ***THE APPID IS SPELLED OUT, AND THE FIRST ATTEMPT ASKED ISPP FOR IT AND
     DID NOT COMPILE - TWICE OVER.***  A preprocessor call in the string was
     one failure; writing the preprocessor function's NAME in this very comment
     was the other, because ISPP expands a brace-hash sequence wherever it
     finds one, comments included, and a bare call with no arguments is
     "Insufficient parameters" pointing at a line of English.  Same family as
     the hash-13 trap recorded at the closing message box.  So the literal
     appears twice in this file, here and in [Setup], and a reader comparing
     them sees the same characters.

     ***HKLM64, NOT HKLM, AND THAT IS MEASURED RATHER THAN REASONED - PLAIN
     HKLM FINDS NOTHING HERE.***  Setup is a 32-BIT process, so an unqualified
     HKLM from [Code] is redirected to SOFTWARE\WOW6432Node, and SD's key is
     not there.  A throwaway Inno probe asked all three on this machine, with
     SD installed as the control:

         HKLM   -> not found      HKLM32 -> not found      HKLM64 -> FOUND

     ***THIS IS THE FAILURE THAT WOULD HAVE LOOKED LIKE A PASS.***  It compiles
     clean, SdWasInstalled is simply always False, TrueUpgrade never fires, and
     the whole of 88 does nothing while every test of it reports success.
     Asking WOW6432Node explicitly does not help either: from a redirected
     process that resolves to WOW6432Node\WOW6432Node.

     The 32-bit view is still asked, second, so a hypothetical 32-bit install
     is not missed; IsWin64 guards it because HKxx64 is only valid on 64-bit
     Windows. *)
  if IsWin64 then
    SdWasInstalled :=
      RegKeyExists(HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}_is1') or
      RegKeyExists(HKLM32, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}_is1')
  else
    SdWasInstalled :=
      RegKeyExists(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}_is1');

  (* AND THE SAME TREATMENT FOR ssh AS OF 16 Aug 2026, FOR A REASON THAT ONLY
     ARRIVED WITH THE MANDATORY INSTALL.

     Tested by looking for the file rather than by asking Windows.
     Get-WindowsCapability -Online REQUIRES ELEVATION - measured 14 Aug 2026 -
     and while Inno happens to be elevated, a file test costs nothing, cannot
     fail for a reason unrelated to the question, and is instant.

     WHY IT IS NOW CACHED.  While ssh was a task, the live test was safe: it
     was read before anything was installed, and the only consumer downstream
     asked WizardIsTaskSelected, which cannot be true on a machine that already
     had a server.  Now the installer installs one itself, so from ssPostInstall
     onwards the live answer is False on EVERY machine and "did we put this
     here?" becomes unanswerable - taking the firewall step and the whole ssh
     report with it, since both must do nothing to a server SD did not install.
     The question is about the machine as we found it, so it is asked once,
     here, exactly as the data tree above is. *)
  SshWasAbsent := not FileExists(ExpandConstant('{sys}\OpenSSH\sshd.exe'));

  (* 30 Aug 26 - AND, IF ONE IS ALREADY HERE, HOW EXPOSED IT ALREADY IS.
     PRE_RELEASE_FIXES 76.  This is the default state of the "allow remote
     access" box on a machine SD is not installing ssh onto, and the owner's
     ruling is that the box shows the truth so that leaving it alone changes
     nothing: "default the box to the current scope".

     ONLY ASKED WHEN THERE IS SOMETHING TO ASK ABOUT.  On a machine with no ssh
     server there is no rule to read, netsh would answer nothing useful, and the
     cost would be paid on every install for an answer nobody reads.

     ssh-firewall.ps1 -Show IS READ-ONLY AND NEEDS NO ELEVATION - it is the one
     mode of that script that does not carry the -Installed gate, precisely
     because it changes nothing.  Its line is
       ssh-firewall: OpenSSH-Server-In-TCP  Enabled=True  Profile=Private  RemoteAddress=Any
     and "RemoteAddress=Any" is the whole of what is being asked.  Anything else
     - a loopback literal, a subnet, a list - is not "open to the network", so
     the test is for Any and everything else counts as restricted.

     A FAILURE TO READ IT MUST DEFAULT TO RESTRICTED, NOT OPEN.  If the query
     does not run, or the rule is missing because the capability has not
     finished registering it, the safe default for a checkbox that OPENS a port
     is unticked.  GetSshRuleIsOpen returns False on every error path and says
     so in its own comment. *)
  if not SshWasAbsent then
    SshRuleWasOpen := GetSshRuleIsOpen
  else
    SshRuleWasOpen := False;

  (* SD DOES NOT SUPPORT UNATTENDED INSTALLATION.  Owner's ruling, 23 Aug 2026,
     in his own words: "unattended deployment is not supported in sd - install
     can only happen at the keyboard or in a remoted session."  There is
     deliberately NO escape switch.

     WHY IT IS A RULING AND NOT A PRECAUTION.  The install ENDS by asking for a
     password - DeinitializeSetup runs the step only when not silent - so a
     silent install finishes with an EMPTY credential register: no account
     reachable over ssh or through the API, and an elevated "sd <command>" at a
     console stops at the credential prompt with nobody to answer it.  The tree
     otherwise looks complete and nothing said a word.  That cost two sessions
     in Aug 2026, handed over as an unexplained hang in SD's start-up, and it
     was neither in start-up nor in SD.

     A WARNING WOULD NOT HAVE DONE.  Nobody reads output from a silent install;
     that is what silent means.  An earlier version of this gate offered
     /NOPASSWORD=yes to proceed anyway, and the owner removed it: a switch that
     buys a credential-less system is a switch somebody will paste from a forum.

     REMOTE DESKTOP IS NOT UNATTENDED and is unaffected - the wizard runs, a
     person answers it.  5.6.2 puts a remoted session on the console's side of
     the line, and that is where installation lives too. *)
  if WizardSilent then
  begin
    Log('SD: refusing a silent install - SD Core does not support unattended ' +
        'installation.  The install ends by asking for a password and there ' +
        'is nobody to ask.');
    SuppressibleMsgBox(
      'SD Core cannot be installed silently.' + #13#10#13#10 +
      'Installing ends by asking for a password, and a silent install has ' +
      'nobody to ask. It would finish with NO password set for any account, ' +
      'and an account without a password cannot be used AT ALL - not at this ' +
      'computer, not over ssh, and not through the SD Core API. SD Core asks ' +
      'for one every time you open the account and will not let a session go ' +
      'on without it.' + #13#10#13#10 +
      'Run the installer normally instead. You can do that at this computer''s ' +
      'keyboard, or through Remote Desktop or similar remote-control software - ' +
      'both work, because a person is there to answer.',
      mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;

  (* SD INSTALLS ONLY BESIDE THE ssh SERVER IT OWNS.  Owner's ruling,
     25 Aug 2026: "I would actually prefer that SD refused to install if
     another ssh server is installed.  It adds a layer of unpredictability.
     If we support only the windows ssh server, then we know what it is that
     is being used and we have control over how it is configured."  And on a
     Microsoft server somebody has already configured: "I lean toward refusing
     in both cases because the pre-existing configuration could defeat our
     security.  If the user wants to change our security policy after the
     fact, that is not on us."

     IT CLOSES A HOLE THAT WAS LIVE.  SshWasAbsent above asks whether
     MICROSOFT's OpenSSH is present, and the rest of this file read that as
     "is there an ssh server".  Beside Bitvise or freeSSHd those are different
     questions: SD concluded there was none, installed Windows OpenSSH, and it
     could not bind port 22 because the other server held it.  The whole access
     path was then broken and nothing in the install said so.

     HERE, AND NOT LATER, BECAUSE HERE IS FREE.  InitializeSetup runs before
     the wizard is drawn and before one file is written, so a refusal costs the
     user nothing but the time to read it.  NO ESCAPE SWITCH, for the reason
     the silent-install ruling above gives.

     THE CHECK IS A SCRIPT, NOT PASCAL HERE, for the reason install-ssh.ps1
     records: a file can be read, parse-checked and TESTED on its own.
     probe-sshpreflight.ps1 exercises both polarities on a throwaway guest.
     It is embedded with dontcopy ([Files]) because it must run before the
     copy step, and installed to {app} as well so it can be re-run by hand. *)
  ExtractTemporaryFile('ssh-preflight.ps1');
  PreflightPs         := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  PreflightScript     := ExpandConstant('{tmp}\ssh-preflight.ps1');
  PreflightReasonPath := ExpandConstant('{tmp}\ssh-preflight-reason.txt');

  if not Exec(PreflightPs,
              '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
              PreflightScript + '" -ReasonFile "' + PreflightReasonPath + '"',
              '', SW_HIDE, ewWaitUntilTerminated, PreflightCode) then
  begin
    (* THE CHECK ITSELF DID NOT RUN.  Treated as a refusal, not waved through:
       the whole point is that this machine is knowable, and a check that did
       not run has established nothing.  Same reasoning as the script's own
       exit 2. *)
    Log('SD: refusing - ssh-preflight.ps1 could not be started.');
    SuppressibleMsgBox(
      'SD Core could not check this computer''s ssh server, so it has not installed ' +
      'anything.' + #13#10#13#10 +
      'SD Core needs the OpenSSH server that ships with Windows, and it checks first ' +
      'that no other ssh server is present and that nobody has already changed ' +
      'how this one is configured. That check could not be run.' + #13#10#13#10 +
      'Nothing on this computer has been changed.',
      mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;

  if PreflightCode <> 0 then
  begin
    PreflightReason := '';
    if FileExists(PreflightReasonPath) then
      LoadStringFromFile(PreflightReasonPath, PreflightReason);
    Log('SD: refusing - ssh-preflight exited ' + IntToStr(PreflightCode) +
        ': ' + String(PreflightReason));
    SuppressibleMsgBox(
      { The #13#10 stays at the END of the line above, never at the start of
        this one: ISPP reads a leading '#' as a preprocessor directive, and
        cycle.ps1 refuses the build for it.  It caught exactly that here on
        25 Aug 2026 - before ISCC ran, which is what that guard is for. }
      'SD Core has not been installed, because of this computer''s ssh server.' + #13#10#13#10 +
      String(PreflightReason) + #13#10 +
      'Why this matters: SD Core configures the ssh server so that accounts signing in ' +
      'over ssh land in SD Core and cannot get a command prompt - and it can only ' +
      'promise that on a server it installed and configured itself.' + #13#10#13#10 +
      'What you can do: remove the other ssh server, or return this computer''s ' +
      'ssh configuration to the way Windows shipped it, and run this installer ' +
      'again.' + #13#10#13#10 +
      'Nothing on this computer has been changed.',
      mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;

  Result := True;
end;

function DataTreeAbsent: Boolean;
begin
  Result := DataTreeWasAbsent;
end;

(* THE OTHER BRANCH, AND THE TWO ARE EXHAUSTIVE.  Every entry in the generated
   upgrade.iss is gated on this; the whole-tree entry in [Files] is gated on
   DataTreeAbsent above.  One or the other fires on every install, never both
   and never neither.

   IT READS THE SAME CACHED ANSWER, which is the point.  DataTreeWasAbsent is
   sampled once in InitializeSetup because a live DirExists is destroyed by
   the first file the installer writes - that bug skipped ~3,260 files and
   still exited 0, and it is recorded where the variable is set.  A second
   function asking Windows again would reintroduce it on the upgrade side,
   where it would be far harder to see: the deletes would run and the copies
   would not. *)
function DataTreeUpgrade: Boolean;
begin
  Result := not DataTreeWasAbsent;
end;

(* 31 Aug 26 - AN INSTALL OVER A LIVE SD, WHICH IS NOT THE SAME QUESTION.
   PRE_RELEASE_FIXES 88.  Owner's ruling: "on an upgrade, just skip this page
   entirely.  If the admin wants to make additional choices, we have given them
   the command line tools."

   ***BOTH HALVES, AND THE SECOND IS THE ONE THAT WAS NEARLY MISSED.***
   DataTreeUpgrade alone would also be true after an UNINSTALL, because the
   uninstaller keeps the data tree on purpose - and by then it has already run
   RemoveAllowGroups, RemoveApiFirewall and RemoveFromPath.  Skipping the page
   there would hand the reader a machine whose ssh confinement, 4243 rule and
   PATH entry had just been removed, with nothing to put them back and no
   question asked.  So that case SHOWS the page, and the owner checked the
   consequence himself: with a server still present the reader simply gets the
   open-the-port question, defaulted from the live scope.

   AND ON THAT PATH THE DEFAULTS ARE HONEST TOO: the uninstall key is gone, so
   UsePreviousTasks has nothing to restore and the boxes come up as declared
   rather than as the last install's answers. *)
function TrueUpgrade: Boolean;
begin
  Result := DataTreeUpgrade and SdWasInstalled;
end;

(* THE PAGE ITSELF.  ShouldSkipPage was removed on 30 Aug 2026 with the mode
   page (see the note further down); this brings it back for the tasks page
   alone.

   ***SKIPPING THE PAGE IS ONLY HALF OF THE RULING, AND ON ITS OWN IT WOULD BE
   WORSE THAN THE DEFECT.***  Inno still initialises every task from its
   declared default PLUS the UsePreviousTasks restoration, and
   WizardIsTaskSelected keeps answering - so hiding the page without gating the
   ACTIONS would turn "visible but inert" into INVISIBLE BUT ACTIVE: firewall
   rules moving from state nobody saw, and install-ssh.ps1 able to install a
   server silently.  The gates are at the [Run] entry, the [Registry] entry,
   the two ApplyXxxFirewall call sites and ApplyAllowGroups, each carrying
   "not TrueUpgrade".

   02 Sep 26 - ApplyAllowGroups JOINED THAT LIST LATE, WHICH IS PRE_RELEASE 118.
   This sentence used to read "the two ApplyXxxFirewall call sites" and was
   accurate about the gates that existed while being wrong about the ones that
   were needed - an upgrade rewrote sshd_config and bounced sshd having just
   told the reader it changed nothing.  A list like this is a claim; when a
   gate is added the claim has to move with it. *)
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpSelectTasks) and TrueUpgrade;
end;

(* 31 Aug 26 - AND THE READY PAGE HAD TO GO WITH IT.  PRE_RELEASE_FIXES 88.

   ***SKIPPING THE TASKS PAGE LEFT THE TASKS SELECTED, AND "Ready to Install"
   LISTS SELECTED TASKS.***  So an upgrade showed a memo promising to add SD to
   the PATH, open port 22 and provide the API - four things the gates above
   make certain it will NOT do.  The owner ran it and said the page "talks
   about additional tasks, but doesn't really explain anything.  Not sure why
   it is there."  He was being generous: it was not merely unexplained, it was
   FALSE, and it is 5.21's rule showing up one page later - a control, or here
   a promise, that cannot act.

   THE TASK MEMO IS DROPPED RATHER THAN THE TASKS DESELECTED.  Deselecting
   would empty the memo too, and would even make the five gates redundant - but
   it works by reaching into the wizard's state to fix a display problem, and
   anything reading WizardIsTaskSelected afterwards would get an answer the
   reader never gave.  The gates say what happens; this says what happens.  Two
   statements of the same fact are better than one statement and one silence.

   A FIRST INSTALL IS UNTOUCHED, deliberately: there the task list is accurate,
   it is the only summary of what was chosen, and Inno's default assembly is
   what every other page on that path was written against. *)
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if not TrueUpgrade then
  begin
    { ***ALL SIX, IN INNO'S ORDER, AND NOT JUST THE TWO THIS INSTALLER HAPPENS
      TO USE.***  Defining this function REPLACES the default assembly
      outright, so naming only Dir and Tasks would silently drop anything a
      later [Components] or [Types] section produced - a regression nobody
      would see, because it removes information rather than adding it.  Written
      to reproduce the default exactly. }
    Result := '';
    if MemoUserInfoInfo   <> '' then Result := Result + MemoUserInfoInfo   + NewLine + NewLine;
    if MemoDirInfo        <> '' then Result := Result + MemoDirInfo        + NewLine + NewLine;
    if MemoTypeInfo       <> '' then Result := Result + MemoTypeInfo       + NewLine + NewLine;
    if MemoComponentsInfo <> '' then Result := Result + MemoComponentsInfo + NewLine + NewLine;
    if MemoGroupInfo      <> '' then Result := Result + MemoGroupInfo      + NewLine + NewLine;
    if MemoTasksInfo      <> '' then Result := Result + MemoTasksInfo      + NewLine + NewLine;
    Exit;
  end;

  Result :=
    'Upgrading the SD Core already installed on this computer.' + NewLine + NewLine +
    Space + 'The program files are replaced.' + NewLine +
    Space + 'Your database, your accounts and your settings are kept.' + NewLine + NewLine +
    'SETUP HAS NOT ASKED ABOUT ssh OR THE API, AND WILL NOT CHANGE THEM.' + NewLine +
    'Who may reach this machine, whether the API is provided, and whether "sd"' + NewLine +
    'runs from any directory are all left exactly as they are now.' + NewLine + NewLine +
    'NEW COMMANDS DO NOT APPEAR IN AN EXISTING ACCOUNT ON THEIR OWN.' + NewLine +
    'An upgrade replaces the shipped vocabulary but does not rebuild the one' + NewLine +
    'each account is using. Sign in and run this ONCE IN EACH ACCOUNT that' + NewLine +
    'needs the new commands, SDSYS included:' + NewLine + NewLine +
    Space + 'update.account' + NewLine + NewLine +
    'It takes no argument and refreshes the account you are in, keeping to' + NewLine +
    'that account''s tier.' + NewLine + NewLine +
    'To change the settings above, in SDSYS as an administrator:' + NewLine + NewLine +
    Space + 'remote.ssh on | off' + NewLine +
    Space + 'remote.api on | local | off' + NewLine +
    Space + 'ssh.server install | remove' + NewLine +
    Space + 'append.sd.path on | off' + NewLine + NewLine +
    'Each reports its current setting, and changes nothing, when given no' + NewLine +
    'keyword.';
end;

function SshServerAbsent: Boolean;
begin
  Result := SshWasAbsent;
end;

{ 30 Aug 26 - THE THREE ANSWERS THE ssh BOXES PRODUCE.  PRE_RELEASE_FIXES 67
  and 76.  They exist so that no other part of this file has to know that one
  reader-facing question is spelled with four [Tasks] entries. }

{ 30 Aug 26 - DOES THIS INSTALL PROVIDE THE API AT ALL?  PRE_RELEASE_FIXES 75.
  One box, two consequences, and they must not drift apart: it picks which
  sd.conf is installed ([Files]) and therefore whether SD opens a listener, and
  it is what ApplyApiFirewall then follows.  A single function so that both read
  the same answer. }
function ApiWanted: Boolean;
begin
  Result := WizardIsTaskSelected('apiremote');
end;

(* 02 Sep 26 - CAN THE API BOX ACT AT ALL?  PRE_RELEASE_FIXES 89, Defect A.
   Owner's ruling, 2 Sep 2026: hide it when it cannot, which is the shape
   sshserver already uses to hide on a machine that has a server.

   ***THE HONEST TEST IS sd.conf's EXISTENCE, NOT THE PATH THAT LED HERE.***
   The [Files] pair that writes sd.conf is onlyifdoesntexist on BOTH arms, so
   the box can move the listener only when there is no sd.conf to preserve.
   Asking that directly is narrower than asking "is this an upgrade", and it
   stays true however the tree came to be here.

   THE PATH IT WAS FILED FOR: uninstall then reinstall with the database KEPT.
   The uninstall key is gone, so SdWasInstalled and TrueUpgrade are both false
   and the tasks page IS shown - while the data tree is present, so sd.conf is
   preserved and ticking "Provide the SD Core API" opened no socket. *)
function ApiConfAbsent: Boolean;
begin
  Result := not FileExists(ExpandConstant('{#DataDir}\sd.conf'));
end;

(* WILL THERE BE AN API LISTENER WHEN THIS INSTALL FINISHES?

   ***THIS EXISTS BECAUSE HIDING THE BOX WOULD OTHERWISE HAVE MADE THE CLOSING
   REPORT LIE, AND IN THE DANGEROUS DIRECTION.***  Three places read ApiWanted
   as "is there an API" - two "no ssh server" paragraphs and the account
   summary - and a hidden task reads as NOT selected.  On a preserved tree
   whose sd.conf runs the API, the account summary would have stated
   "Nothing can reach this account from another machine", which is a false
   claim of isolation.  Fixing Defect A without this would have replaced an
   inert tickbox with a wrong security sentence: a worse bargain.

   IT READS THE FILE RATHER THAN GUESSING FROM THE PATH.  stage.py ships two
   variants and says which is which in as many words - "full (APIPORT=4243) and
   stand-alone (APIPORT unset)" - so an ACTIVE APIPORT line is the honest test,
   and a commented or valueless one is not a listener.  Where there is no
   sd.conf to read, the box is the only answer there is, and it is offered. *)
function ApiConfHasListener: Boolean;
var
  Lines: TArrayOfString;
  I, Eq: Integer;
  L: String;
begin
  Result := False;
  if not LoadStringsFromFile(ExpandConstant('{#DataDir}\sd.conf'), Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    L := Trim(Lines[I]);
    if L <> '' then
    begin
      if (Copy(L, 1, 1) <> '#') and (Copy(L, 1, 1) <> ';') then
      begin
        if Pos('APIPORT', Uppercase(L)) = 1 then
        begin
          Eq := Pos('=', L);
          if Eq > 0 then
          begin
            Result := Trim(Copy(L, Eq + 1, Length(L))) <> '';
            Exit;
          end;
        end;
      end;
    end;
  end;
end;

function ApiListenerAfterwards: Boolean;
begin
  if ApiConfAbsent then
    Result := ApiWanted
  else
    Result := ApiConfHasListener;
end;

{ 30 Aug 26 - MAY OTHER COMPUTERS REACH IT?  PRE_RELEASE_FIXES 75.

  SEPARATE FROM ApiWanted ON PURPOSE, and the two answer different questions:
  ApiWanted decides whether SD opens a socket at all (which sd.conf is
  installed), this decides only the FIREWALL SCOPE of a socket that exists.
  Collapsing them is what cost the local-only state in the first place.

  NO PARENT TEST HERE.  Inno unchecks a child whose parent is unchecked, so
  this cannot be true while ApiWanted is false - and re-deriving the parent
  would be a second opinion that could disagree with the wizard the user
  actually saw. }
function ApiNetworkWanted: Boolean;
begin
  Result := WizardIsTaskSelected('apiremote\apinetwork');
end;

{ Was the rule already open when we arrived?  Only meaningful when a server was
  already here - see the variable's own comment. }
function SshCurrentlyOpen: Boolean;
begin
  Result := SshRuleWasOpen;
end;

{ ***DOES THIS MACHINE END THE INSTALL WITH AN ssh SERVER?***  Either it already
  had one, or the reader ticked the box to install one.  This is what the
  capability install is gated on now, and it is the owner's ruling of 30 Aug
  2026 replacing "install it whenever it is absent": PRE_RELEASE 67's complaint
  was that declining ssh still installed the server, because the install step
  tested SshServerAbsent and never tested the box at all. }
function SshServerWanted: Boolean;
begin
  Result := WizardIsTaskSelected('sshserver');
end;

function SshServerPresentAfterwards: Boolean;
begin
  Result := (not SshWasAbsent) or SshServerWanted;
end;

{ ***MAY OTHER COMPUTERS REACH IT?***  Three entries can carry this answer and
  exactly one of them can be visible on any given run, because their Checks
  partition on SshServerAbsent and then on SshCurrentlyOpen.  ORed rather than
  chosen by re-testing those conditions here: re-deriving which box SHOULD have
  been shown would be a second copy of the partition, and the two copies would
  drift.  Asking all three asks the wizard what it actually displayed.

  AND IT CANNOT BE TRUE WITHOUT A SERVER.  sshserver\sshremote is a child task,
  so Inno unchecks it whenever its parent is unchecked - which is the whole of
  "allowing remote access should not be an option if they choose not to install
  the ssh server".  The AND below is belt to that brace, and it is cheap: it
  makes the property hold even if somebody later flattens the child. }
function SshRemoteWanted: Boolean;
begin
  Result := (WizardIsTaskSelected('sshserver\sshremote') or
             WizardIsTaskSelected('sshremoteshut') or
             WizardIsTaskSelected('sshremoteopen'))
            and SshServerPresentAfterwards;
end;

{ Registered by the OpenSSH capability, not by us.  Its absence just after an
  install is what "a restart is outstanding" looks like from here - measured
  14 Aug 2026, when Add-WindowsCapability completed and the service did not
  exist until after a reboot.  Read from the registry rather than by shelling
  out to sc.exe: it is the same fact, and it costs nothing. }
function SshServiceRegistered: Boolean;
begin
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Services\sshd');
end;

{ ---------------------------------------------------------------------------
  How SD will be used, and then the page that says what this will do
  --------------------------------------------------------------------------- }

var
  SummaryPage: TOutputMsgMemoWizardPage;

(* 30 Aug 26 - THE MODE PAGE IS GONE, AND WITH IT ModePage, FullRadio,
   StandaloneRadio, ModeMemo, StandaloneChosen, StandaloneWasMarked,
   WriteStandaloneMarker and the '$standalone' marker.  PRE_RELEASE_FIXES 75,
   the owner's ruling of 30 Aug 2026:

     "we should remove the standalone option - if the user does a full install
      and leaves both ssh and api unchecked, there will be no ssh server install
      and is basically the same as a standalone install"

   THE THREE DIFFERENCES IT USED TO CARRY ARE ALL ANSWERED ELSEWHERE NOW.
   (1) The ssh server: PRE_RELEASE 67, the sshserver box gates the capability
       install, so leaving it blank installs none.
   (2) CREATE.ACCOUNT's blanket refusal with message 10100: removed from
       CREATEA, which is what read the marker.
   (3) APIPORT: the apiremote box now picks between the two sd.conf variants,
       so an unticked box means no listener at all - "the api box unchecked
       should mean not provide the service at all - the port should not be left
       open."

   ***AND WITH THE PAGE GOES THE ONLY IRREVERSIBLE DECISION THE INSTALLER ASKED
   ANYONE TO MAKE***, the one its own memo had to warn "cannot be changed from
   inside SD afterwards".  The replacement path is the owner's: "redoing the
   install to allow ssh or api - better path than the existing standalone to
   full."

   ONE WRINKLE THAT PATH HITS, AND IT IS THE API HALF ONLY.  sd.conf is
   onlyifdoesntexist, precisely so a reinstall never discards a configuration
   the user edited - so a reinstall does NOT turn APIPORT back on by itself.
   The ssh half needs nothing, because the ssh boxes read machine state.  Left
   as documentation rather than code: the installer does not edit a config file
   the administrator owns, and uncommenting one APIPORT line is a smaller and
   more visible act than a silent rewrite.  Recorded in PRE_RELEASE 75. *)

(* 30 Aug 26 - ShouldSkipPage IS GONE TOO, AND ITS ABSENCE IS THE WHOLE OF IT.
   It existed only to hide the mode page on an upgrade; with no mode page there
   is nothing it could skip, and an event function that always answers False is
   the same as not defining one.  PRE_RELEASE_FIXES 75. *)

(* AFTER THE MODE PAGE AND BEFORE THE TASKS PAGE, AND THAT ORDER IS THE POINT.

   It said "after wpWelcome" until 25 Aug 2026, which was true until the mode
   page went in between.  It is still the second page the reader sees; what
   changed is that by the time they see it the mode is known, so it describes
   the install they chose instead of the only one there used to be.

   Inno already provides the last-chance page: Ready to Install lists the
   destination and the ticked tasks with Cancel beside them.  What it cannot
   show is everything this installer does that is NOT a task - two local groups,
   a group membership, two user-rights denials, an ACL rewrite that strips
   inherited access from the data tree, a Windows service, and the OpenSSH
   install.  A summary at the end would come after the reader had already
   decided; the ssh exposure checkbox in particular is a decision they were
   being asked to take with no context at all.

   IT ALSO CARRIES THE THINGS THAT USED TO BE SAID ONLY AT THE END, where they
   were too late to act on: that Windows will not apply the sdusers membership
   until the user signs out, and that the OpenSSH install can take minutes and
   usually wants a restart before any account can sign in.  The closing dialog
   still says both - somebody who has just clicked through six pages should not
   have to remember - but saying it first is the difference between a stated
   cost and a surprise.

   A MEMO PAGE RATHER THAN InfoBeforeFile, which would mean shipping an .rtf and
   teaching stage.py to stage it.  This needs no new file and cannot get out of
   step with the script that does the work.

   Do not start a line here with a "#" - ISPP reads it as a preprocessor
   directive and a wrapped string constant becomes "Unknown preprocessor
   directive".  The trap is recorded at the closing MsgBox; every #13#10 below
   is mid-line for that reason. *)

(* 25 Aug 26 - IT TAKES THE MODE AS AN ARGUMENT, AND THAT IS THE WHOLE DEFENCE
   AGAINST THE FAULT THIS PAGE KEEPS HAVING.  The comment inside records four
   occasions on which this text went on asserting something that had stopped
   being true.  A single text with the ssh paragraphs edited to hedge would
   have been a fifth: it would have had to describe both installs at once, and
   be read by somebody doing neither.

   The common paragraphs are written ONCE and the mode picks between the blocks
   that genuinely differ.  Two whole copies of this page was the alternative,
   and keeping two copies of a text with this history in step is not a thing to
   take on. *)
{ 30 Aug 26 - THE Standalone PARAMETER IS GONE.  PRE_RELEASE_FIXES 75.  It took
  the mode as an argument "so the page cannot describe the other one"; with one
  mode there is no other one, and the three branches it fed have collapsed to
  their surviving arm. }
function DisclosureText: String;
var
  M: String;
begin
  (* NOT WRAPPED BY HAND, AND THAT IS THE POINT.  CORRECTED 16 Aug 2026 on the
     owner seeing it: the first version broke every line at about 50 characters
     because the memo width was a guess the compiler cannot check, and the guess
     was far too narrow - a thin column of text in a wide control, with most of
     the page unused.

     The control word-wraps.  So each paragraph below is ONE line and the memo
     fills whatever width it actually has, at any DPI and any wizard style -
     which is a property rather than another guess.  The source lines are broken
     with "+" for readability; those breaks put nothing in the string.

     THE INDENTS WENT WITH IT, and had to.  A two-space indent only survives on
     the first line of a wrapped paragraph, so indented text under a heading
     comes out with one line in and the rest flush left, which looks worse than
     no indent at all.  Structure is carried by blank lines and capitalised
     headings instead.

     So: do not reintroduce a line break inside a paragraph here, and do not
     indent one.  Both look fine in the source and wrong on screen. *)
  { 25 Aug 26 - "you can change this" WAS FALSE AND THE OWNER CAUGHT IT ON THE
    PAGE.  DisableDirPage=yes and UsePreviousAppDir=no are set at the top of
    this file, so the wizard never shows a directory page and there is nothing
    to change.  The text had gone on saying otherwise since before that pin
    went in.

    Both locations are now described the same way, because they now behave the
    same way.  /DIR= on the command line still overrides it - that is Inno's
    behaviour and is deliberately left alone - but it is not something this
    page should offer, being an explicit act by somebody who has read the
    reasoning, not a wizard page a user clicks past.

    THAT IS THE SECOND FALSE STATEMENT FOUND ON THIS PAGE IN ONE DAY; the
    other was "SD LEAVES IT ALONE" about an existing ssh server.  This page
    accumulates claims that quietly stop being true when something else in the
    file changes, exactly as the wpSelectTasks MsgBox does - and its comment
    has been recording that pattern for three rewordings.  When changing
    behaviour, READ THIS PAGE. }
  M := 'WHERE THINGS GO' + #13#10#13#10 +
       'Program files:  C:\Program Files\SD  - fixed, it cannot be moved.' + #13#10 +
       'Database:  C:\ProgramData\SD  - fixed, it cannot be moved.' + #13#10#13#10 +

       'WINDOWS GROUPS, AND ONE THING YOU MUST DO AFTERWARDS' + #13#10#13#10 +
       'Creates the group "sdusers" and adds you to it. That membership is what ' +
       'grants access to the database. Windows only applies a new group when you ' +
       'sign in, so YOU MUST SIGN OUT AND BACK IN, or restart, before SD Core will ' +
       'run. Until then it reports that it cannot open its files.' + #13#10#13#10;

  { THE sdsshonly PARAGRAPH IS MODE-SPECIFIC BECAUSE THE GROUP'S JOB IS.  It
    confines the Windows accounts CREATE.ACCOUNT USER makes to ssh, and a
    stand-alone system refuses that verb - so the group is still created, the
    installer's steps and the uninstaller both being unconditional, and it
    stays empty for the life of the install.  "Accounts SD creates go in it",
    on a system that creates none, would have been the fifth false statement
    this page has carried. }
  M := M + 'Creates the group "sdsshonly" and denies its members the right to sign in at the console or over Remote Desktop. Accounts SD Core creates go in it. Your own account does not.' + #13#10#13#10;

  M := M +
       'PERMISSIONS ON THE DATABASE' + #13#10#13#10 +
       'Removes inherited permissions from C:\ProgramData\SD and grants access to ' +
       'SYSTEM, administrators and sdusers only. Without this the database would ' +
       'be readable by anyone with an account on this machine.' + #13#10#13#10 +

       'SERVICE AND PATH' + #13#10#13#10 +
       'Installs a Windows service that runs SD Core and starts it again after every ' +
       'restart. There is nothing to start by hand.' + #13#10#13#10 +
       'Adds SD Core to the system PATH, unless you clear that option.' + #13#10#13#10;

  (* THE ssh AND NETWORK SECTION - the half the two installs genuinely disagree
     about, and the reason this function takes an argument at all.

     THE FULL BRANCH IS THE EXISTING TEXT, WORD FOR WORD.  The owner has read it
     on screen and it has been reworded four times to catch up with behaviour;
     it is not re-drafted here to make the two branches look alike. *)
  { 30 Aug 26 - ONE ARM NOW, AND ITS ssh SECTION IS REWRITTEN RATHER THAN
    TRIMMED.  PRE_RELEASE_FIXES 67, 75 and 76.  The stand-alone arm went with
    the mode; what was left said "INSTALLED, NOT OPTIONAL" and "that option is
    not offered", and both of those became false on the same day.  A page whose
    whole purpose is to be believed cannot carry either. }
    M := M +
       'OPENSSH SERVER - YOUR CHOICE' + #13#10#13#10 +
       'SD Core accounts sign in two ways: over ssh, or over the SD Core API. Both ' +
       'are offered on the next page, and neither is required to install SD Core - ' +
       'administrators use SD Core by typing "sd" at an elevated prompt, including ' +
       'creating and managing accounts, with or without either one.' + #13#10#13#10 +
       'So an account you create needs ssh OR the API before it can sign in. You can ' +
       'set accounts up first and turn a transport on later: a grant made ahead of ' +
       'time takes effect the moment the transport is on. With neither, only ' +
       'administrators can use this machine.' + #13#10#13#10 +
       'IF THIS MACHINE HAS NO SSH SERVER, the options page offers to install ' +
       'one. It is downloaded from Windows Update and CAN TAKE SEVERAL MINUTES ' +
       'with nothing on screen. Do not stop it part way, and IT USUALLY NEEDS A ' +
       'RESTART - until you restart, nobody can sign in over ssh yet.' + #13#10#13#10 +
       'WHO MAY REACH IT IS A SECOND, SEPARATE CHOICE on the same page, and it ' +
       'is offered whether SD Core installs the server or finds one already here. ' +
       'A server SD Core installs is reachable only from this machine unless you ask ' +
       'otherwise. For a server that is already here, the box STARTS OUT ' +
       'MATCHING THIS COMPUTER''S CURRENT FIREWALL RULE, so leaving it alone ' +
       'changes nothing either way.' + #13#10#13#10 +
       'IF THIS MACHINE ALREADY HAS A DIFFERENT SSH SERVER, SD Core WILL NOT INSTALL ' +
       'AT ALL. It says so and stops, before changing anything. SD Core needs to know ' +
       'how the ssh server is configured, and it can only know that about the one ' +
       'Windows ships. The same applies if somebody has already changed how this ' +
       'computer''s Windows ssh server is configured.' + #13#10#13#10 +

       'IF YOU INSTALL THE ssh SERVER, EVERY SSH SESSION GOES STRAIGHT INTO SD Core, ' +
       'AND THAT PART IS NOT AN OPTION' + #13#10#13#10 +
       'SD Core limits ssh to SD Core users and administrators, and puts every ssh session ' +
       'straight into SD Core instead of a command prompt. That is the point of ' +
       'confining ssh to SD Core: an account SD Core creates cannot get a shell ' +
       'on this computer.' + #13#10#13#10 +
       'THE COST, SAID PLAINLY, AND ONLY IF YOU INSTALL THE SERVER: scp and sftp ' +
       'STOP WORKING FOR EVERYONE on this computer, because the command is forced ' +
       'and there is no subsystem left to run. Remote-control tools that copy files ' +
       'are unaffected, and so are the console and Remote Desktop.' + #13#10#13#10 +
       'DECLINE THE ssh SERVER ON THE NEXT PAGE AND NONE OF THAT HAPPENS. SD Core ' +
       'then touches no ssh configuration at all, opens no port, and leaves scp and ' +
       'sftp exactly as they are. The ssh server is off by default.' + #13#10#13#10 +
       'SD Core''s settings go in a marked block of their own, and any existing ' +
       'sshd_config is kept beside it as sshd_config.before-sd. ' +
       'Uninstalling SD Core removes its block and restarts the ssh server, which ' +
       'leaves the file as it was; the copy is there if you would rather put it ' +
       'back yourself.' + #13#10#13#10;

  { 29 Aug 26 - THE ACCOUNTS ARE NAMED HERE NOW.  PRE_RELEASE_FIXES 39: this
    listed the database, the ssh server and sdusers, and said nothing about the
    Windows accounts CREATE.ACCOUNT had made - so an administrator reading it
    had no reason to think there was anything else to clean up.  It was wrong
    whichever way the new prompt is answered, which is why it is fixed with it
    rather than after it. }
  M := M + 'WHAT UNINSTALLING DOES NOT REMOVE' + #13#10#13#10;
  { 30 Aug 26 - "the ssh server" IS HEDGED NOW RATHER THAN BRANCHED.  There is
    one arm, and whether an ssh server was installed is a box on the tasks page
    rather than a mode, so the sentence says "if SD installed one" instead of
    asserting it either way.  PRE_RELEASE_FIXES 67 and 75. }
    { 30 Aug 26 - ALL FOUR GROUPS ARE NAMED NOW, NOT ONE.  PRE_RELEASE_FIXES 74.
      Measured in the after-capture of the real uninstall that closed 39:
      sdusers, sdssh, sdapi and sdsshonly ALL still exist afterwards, and this
      sentence named only sdusers - so three of the four were unstated in the
      one document whose whole job is to be complete about what is left behind.

      sdsshonly IS WORTH NAMING ON ITS OWN ACCOUNT.  It carries
      SeDenyInteractiveLogonRight and SeDenyRemoteInteractiveLogonRight
      (deny-logon.ps1:29), so it is a deny-logon group left on the machine by
      software that has removed itself.  Harmless while empty, and exactly the
      thing an administrator auditing the box afterwards would want told.

      NAMING THEM IS NOT THE WHOLE FIX AND THIS DOES NOT PRETEND IT IS.  The
      entry offers "either remove the three, or name them"; REMOVING them is a
      behaviour change and the owner's call, and sdusers has a stated reason to
      stay that the other three do not share (sd.iss:3506 - deleting it "would
      orphan the permissions on their own database"). }
    M := M + 'Your database, the ssh server if SD Core installed one, the Windows accounts SD Core created - with their sdu_ and sdg_ groups and their profiles - and ONE GROUP: sdusers. Removing the database is offered separately and defaults to keeping it, and removing the accounts is offered separately after it, also defaulting to keeping them.' + #13#10#13#10 +
         'sdusers stays because deleting it would orphan the permissions on your database. The other three groups SD Core made - sdssh, sdapi and sdsshonly - ARE removed, without asking, because nothing reads them once SD Core is gone. That matters most for sdsshonly: it denied its members the console and Remote Desktop, so any account you keep gets those back and becomes an ordinary Windows account, which is what the rest of this page describes.' + #13#10#13#10 +
         'Accounts you keep are ordinary Windows accounts once SD Core is gone: they keep their passwords, and the ssh confinement that limited them to SD Core is removed with the rest of SD Core''s configuration. Your own account is never removed by that prompt.' + #13#10#13#10;

  { KEPT COMMON, DELIBERATELY.  It is true of a stand-alone system too - the
    installing user is one member of sdusers and an administrator can add
    others by hand - and a warning is the wrong thing to soften on the strength
    of "there is probably only one person here". }
  M := M +
       'ONE LIMIT WORTH KNOWING BEFORE YOU RELY ON IT' + #13#10#13#10 +
       'SD Core users are not isolated from each other. Every SD Core process opens the ' +
       'database as the person running it, so anyone who can use SD Core on this ' +
       'machine can read another account''s files outside SD Core. Do not use SD Core ' +
       'accounts as a privacy boundary between people who should not see each ' +
       'other''s data.';

  Result := M;
end;

(* 30 Aug 26 - ModeChoiceText IS GONE WITH THE PAGE IT FILLED.
   PRE_RELEASE_FIXES 75.  Its "FULL INSTALLATION" half described what every
   install now does and is said by DisclosureText; its "STAND-ALONE" half
   described a mode that no longer exists.  Two things it carried are worth
   keeping and have been moved rather than dropped: the ssh cost to scp and
   sftp, which DisclosureText already states, and the sentence about what an
   install with no ssh server can and cannot do, which is now in SshReport's
   closing text where it is true of a real install rather than of a mode. *)

procedure InitializeWizard;
begin
  (* 30 Aug 26 - THE MODE PAGE AND ITS TWO RADIO BUTTONS ARE GONE, AND THE
     DISCLOSURE PAGE IS BACK ON wpWelcome WHERE IT SAT BEFORE 25 Aug 2026.
     PRE_RELEASE_FIXES 75.  There is one installation now, so there is nothing
     to choose between here and no reason to make the reader read two
     descriptions of it.

     THE ORDER THAT MATTERED IS PRESERVED BY THE MOVE, NOT BROKEN BY IT.  The
     disclosure page had to come AFTER the mode choice, because it describes an
     ssh install a stand-alone reader was about to decline.  With the choice
     gone the page describes what every install does, so wpWelcome is the right
     anchor again - and it still lands BEFORE wpSelectTasks, which is what the
     ssh boxes need: the reader is told what SD does to ssh before being asked
     how far to open it. *)
  SummaryPage := CreateOutputMsgMemoPage(wpWelcome,
      'Before you install',
      'What SD Core changes on this computer',
      'Setup changes Windows itself, not only its own folders. All of it is listed below. ' +
      'Nothing has happened yet - Cancel stops without changing anything.',
      DisclosureText);

  { 1 Sep 26 - MORE AIR BETWEEN THE TASKS.  Owner, looking at the wizard: the
    rows ran together, worst where the wrapped ssh label met its child box.  A
    taller minimum row height separates them; taken from the control's own value
    and nudged with ScaleY so it is right at any DPI, and set ONCE here rather
    than in CurPageChanged so revisiting the page does not keep adding to it. }
  WizardForm.TasksList.MinItemHeight := WizardForm.TasksList.MinItemHeight + ScaleY(6);
end;

{ ---------------------------------------------------------------------------
  Install
  --------------------------------------------------------------------------- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Exe: String;
  Code: Integer;
begin
  Result := '';
  NeedsRestart := False;

  { An upgrade replaces sd.exe and the MSYS2 DLLs.  A running server holds them
    open, and a half-replaced runtime is a worse outcome than a failed install. }
  Exe := ExpandConstant('{app}\usr\bin\sd.exe');
  if FileExists(Exe) then
    Exec(Exe, '-stop', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

{ Deny the sdsshonly group the console and Remote Desktop, and return what to
  tell the user if it did not happen.  PROJECT_STATUS.md 5.6.2, 7 step 3.

  MOVED OUT OF [Run] 17 Aug 2026, WHICH IS THE WHOLE OF THIS CHANGE.  The
  script was always correct - it checks every NTSTATUS and throws, so its exit
  code means something - but a [Run] entry discards the exit code, so the one
  thing this step could not do was report having failed.  sd.iss carried a
  comment claiming CurStepChanged checked it; that claim was corrected in place
  on 16 Aug 2026 and the check itself is what this supplies.

  WHAT IT COSTS WHEN IT FAILS, and why it is worth a paragraph in the closing
  box: an account in sdsshonly on a machine where the deny rights never landed
  is NOT confined to ssh at all.  It can sign in at the console like anyone
  else.  That is a quiet weakening rather than a broken install - which is
  precisely why nobody would notice it, and why it must say so out loud.

  NOT FATAL, on the same reasoning as the OpenSSH step: a machine where user
  rights cannot be set should still get a working SD with the restriction
  absent, rather than a failed install.

  THE READ-BACK LIVES IN verify-sshonly.ps1, NOT HERE.  Confirming the rights
  are present afterwards needs LsaEnumerateAccountRights, and that script
  already dumps and checks them - so repeating it here would be a second
  implementation of the same assertion, to be kept in step with the first. }
function ApplyDenyLogon: String;
var
  Code: Integer;
  Ps, Script: String;
begin
  Result := '';
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\deny-logon.ps1');

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" sdsshonly',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  Result := 'SD Core accounts were NOT confined to ssh (code ' + IntToStr(Code) + '). ' +
            'They can sign in at the console and over Remote Desktop like any other ' +
            'Windows account. SD Core itself is installed and working. To apply it, from an ' +
            'ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" sdsshonly' + #13#10#13#10;
end;

{ Create sdssh and sdapi - the two groups that say which REMOTE route an
  account may use - and seed sdssh from sdusers.  21 Aug 2026.

  IT MUST RUN BEFORE ApplyAllowGroups AND THAT IS NOT A PREFERENCE.  From this
  release sshd's AllowGroups names sdssh instead of sdusers.  On a machine that
  already has SD, every account is in sdusers and none is in sdssh - so if the
  AllowGroups line is written first, sshd is restarted pointing at a group with
  nobody in it and EVERY EXISTING ACCOUNT LOSES ssh at that instant.  The
  seeding in the script is what makes the change invisible to a working
  deployment; the ordering here is what lets the seeding happen in time.

  NOT IN [Run] BESIDE sdsshonly, for a reason worth keeping: the script seeds
  only the group IT created, because "was this group here a moment ago" is the
  only honest test for "does this installation predate the split".  Creating it
  in [Run] would answer that question wrongly - the script would find the group
  present, decline to seed, and produce exactly the empty-AllowGroups lockout
  above.

  NOT FATAL, like the two ssh steps below.  A failure leaves ssh restricted to
  whoever is in sdssh, which the script prints, and the recovery is one
  net localgroup command that it also prints. }
function SyncRouteGroups: String;
var
  Code: Integer;
  Ps, Script: String;
begin
  Result := '';
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\sync-route-groups.ps1');

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  Result := 'The ssh and API access groups were NOT set up (code ' + IntToStr(Code) + '). ' +
            'sshd allows the group "sdssh", so until it has members, ssh will be ' +
            'refused to everyone except administrators. SD Core itself is installed and ' +
            'working. To repair it, from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '"' + #13#10#13#10;
end;

{ Applies the AllowGroups block and returns what to tell the user, or '' if the
  task was not selected.  PROJECT_STATUS.md 5.6.2.

  RUN FROM [Code] AND NOT AS A [Run] ENTRY, because the exit code is the whole
  point.  allow-ssh-groups.ps1 has THREE outcomes, not two, and the middle one
  is the likely one on a fresh machine: 2 means "refused, and here is why" -
  usually that OpenSSH needs a restart before sshd has ever run, so there is no
  sshd_config to edit yet.  A [Run] entry would discard that and the user would
  tick a box and silently get nothing, which is exactly the failure the OpenSSH
  step made for its whole life.

  It runs even in a silent install; only the reporting is skipped. }
function ApplyAllowGroups: String;
var
  Code: Integer;
  Ps: String;
begin
  Result := '';

  { 25 Aug 26 - A STAND-ALONE INSTALL DOES NOT TOUCH sshd_config AT ALL, and
    that is the promise the mode page makes in as many words: "no ssh server is
    installed and no ssh configuration is touched ... scp and sftp go on
    working".  Forcing the SD command here is precisely what stops scp working,
    so this is the step that promise is about.

    IT RETURNS '' RATHER THAN A MESSAGE.  There is nothing to report about work
    that was correctly not done; SshReport says the one thing worth saying about
    an install with no ssh server, in one place. }

  { 30 Aug 26 - RE-KEYED FROM StandaloneChosen.  PRE_RELEASE_FIXES 67 and 75.
    The question this asked has not changed - "is there an ssh server here for
    SD to configure?" - only the thing that answers it.  It used to be the mode;
    it is now the machine plus the sshserver box, which is the same question
    asked directly.  With no server there is no sshd_config to write, and
    writing one would be configuring a service that does not exist. }
  if not SshServerPresentAfterwards then
    Exit;
  { 25 Aug 26 - THE TASK GATE IS GONE BECAUSE THE TASK IS GONE.  This used to
    read "if not WizardIsTaskSelected('limitssh') then Exit", and before that
    it named a subtask that no longer existed - a stale name here would have
    read as "the user did not tick it" for ever, silently.  Now there is no
    box to tick: SD's ssh model applies on every install, and the "Before you
    install" page says so instead of a checkbox implying a choice.

    WHAT USED TO CARRY 5.9 HERE, AND WHAT CARRIES IT NOW.  The default-ticked
    box was the user's way to decline on a machine whose ssh server SD did not
    install.  InitializeSetup now REFUSES that machine outright
    (ssh-preflight.ps1), so it never reaches this line, and the only machine
    that does is one whose ssh server SD installed and nobody else has
    configured.  allow-ssh-groups.ps1's second refusal stays as a backstop for
    hand-running the script; it is no longer the thing standing between SD and
    somebody else's sshd_config, because that machine is turned away earlier. }

  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed' +
                  ' -SdExe "' + ExpandConstant('{app}\usr\bin\sd.exe') + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'ssh could NOT be limited to SD Core users and administrators: the script did not run.';
    Exit;
  end;

  if Code = 0 then
    { 25 Aug 26 - "Any existing", NOT "The original".  Owner's wording, on
      reading this box during the no-ssh guest run.  "The original" implies the
      reader had an sshd_config of their own, and on the machine this message
      most often appears on there was no ssh server at all ten minutes earlier -
      the file was created by the OpenSSH install, not by them.  "Any existing"
      is true either way. }
    { 1 Sep 26 - "sdssh", NOT "sdusers".  PRE_RELEASE_FIXES 117.  This line said
      sdusers and had done since before 21 Aug 2026, when allow-ssh-groups.ps1
      was deliberately changed the other way: :130 writes @('sdssh', admins)
      under a comment at :118 reading "sdssh, NOT sdusers".  The message was
      left behind by that change, and read back off the guest on 1 Sep the live
      file says AllowGroups sdssh VIRTUAL\sdssh Administrators VIRTUAL\...
      IT MATTERED MORE THAN A NAME.  The 21 Aug ruling split "may read SD's
      files" from "may ssh into this machine" so ssh could be withdrawn without
      taking the database away - create.account joins both, modify.account
      <account> no.ssh removes only sdssh.  Naming sdusers here re-welds them,
      and since EVERY SD account is in sdusers a reader who believed it would
      both over-read who can reach the machine and add the wrong group when
      granting access. }
    Result := 'ssh is now limited to members of "sdssh" and the administrators group. ' +
              'Any existing sshd_config was kept as sshd_config.before-sd.'
  else if Code = 2 then
    { The common case on a machine that has just been told to restart: sshd
      writes its config on first start, so there is nothing to edit yet. }
    Result := 'ssh was NOT limited, and nothing was changed. The most likely reason is ' +
              'that OpenSSH has not started yet and has no configuration file - restart, ' +
              'then run this from an elevated prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed' + #13#10#13#10 +
              'It also refuses if sshd_config already says who may connect, in which case ' +
              'that setting is somebody else''s and has been left alone.'
  else
    Result := 'Limiting ssh FAILED and sshd_config was left as it was. Run this from an ' +
              'elevated prompt to see why:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed';
end;

{ Scope the OpenSSH firewall rule to match the checkbox, and return what to tell
  the user.  PROJECT_STATUS.md 5.9.

  ONLY IF SD INSTALLED THE SERVER.  The rule belongs to the ssh server, and "we
  do not touch an ssh server we did not install" covers its firewall rule as
  squarely as it covers sshd_config - restricting the rule of a server that
  predates SD would break somebody's remote access just as thoroughly as
  editing their config would.  SshWasAbsent, not SshServerAbsent evaluated now,
  which by this point answers False on every machine.

  RUN FROM [Code] LIKE ApplyAllowGroups AND FOR THE SAME REASON: the exit code
  distinguishes three outcomes and the middle one is likely on a fresh machine.
  It is also fast, so it needs no StatusMsg - which is what kept the OpenSSH
  install itself in [Run]. }
function ApplySshFirewall: String;
var
  Code: Integer;
  Ps, Args: String;
  Wanted: Boolean;
begin
  Result := '';

  { 30 Aug 26 - THERE IS NOTHING TO SCOPE IF THERE IS NO SERVER.
    PRE_RELEASE_FIXES 67.  The reader can now decline the capability, and on
    that install port 22 belongs to nobody: writing a rule for a service that
    does not exist would be the same lie in the other direction. }
  if not SshServerPresentAfterwards then
    Exit;

  { 30 Aug 26 - AND THE "not SshWasAbsent" EXIT IS GONE, WHICH IS THE WHOLE OF
    PRE_RELEASE_FIXES 76.  It used to return here whenever the machine already
    had a server, so on a reinstall - or on any machine with ssh already on it -
    the installer asked nothing and set nothing, and whatever scope the rule
    happened to carry simply persisted.  The owner's ruling of 30 Aug 2026 is
    that the choice must be offered in that case too:

      "if an ssh server is installed, the user should have a separate choice to
       allow remote access."

    ***5.9 IS NARROWED, NOT ABANDONED, AND THE NARROWING IS WHAT MAKES IT SAFE.***
    "We never reconfigure or restart an ssh server we did not install" exists to
    stop SD breaking a server a site runs for its own reasons.  That risk is real
    here - OpenSSH-Server-In-TCP is Windows' shared rule, not one of ours, so
    restricting it would cut off the site's own ssh - and it is answered by the
    DEFAULT rather than by refusing to act: the box is pre-set from the rule's
    current scope (GetSshRuleIsOpen), so an installer who touches nothing changes
    nothing.  A rule that was open stays open; one that was loopback-only stays
    loopback-only.  Only a deliberate click moves it, which is exactly the
    decision 76 said there was no way to make.

    WHAT IS STILL NOT DONE TO A FOREIGN SERVER: its configuration.  sshd_config
    is ApplyAllowGroups' business and it keeps its own rules; this is the
    firewall alone. }

  Wanted := SshRemoteWanted;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
          ExpandConstant('{app}\ssh-firewall.ps1') + '" -Installed';
  if Wanted then
    Args := Args + ' -Open'
  else
    Args := Args + ' -Restrict';

  if not Exec(Ps, Args, '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'Who may reach ssh could NOT be set: the script did not run. ' +
              'Windows left port 22 open to your local network, which is its own default.' + #13#10#13#10;
    Exit;
  end;

  if Code = 0 then
  begin
    if Wanted then
      Result := 'Other computers on your network CAN now connect to this one over ssh, ' +
                'because you asked for that.' + #13#10#13#10
    else
      Result := 'ssh can be reached FROM THIS COMPUTER ONLY. Nothing on your network can ' +
                'connect to it. To change that later, run this from an elevated prompt:' + #13#10#13#10 +
                '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Open' + #13#10#13#10;
  end
  else if Code = 2 then
    { The likely case when a restart is outstanding: the capability has not
      finished registering its firewall rule, so there is nothing to scope. }
    Result := 'Who may reach ssh has NOT been set yet, because Windows has not finished ' +
              'registering the ssh firewall rule. Restart, then run this from an elevated prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Restrict' + #13#10#13#10
  else
    Result := 'Setting who may reach ssh FAILED, and Windows'' own default is in force - ' +
              'port 22 open to your local network. Run this from an elevated prompt to see why:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Restrict' + #13#10#13#10;
end;

{ WHO MAY REACH THE API PORT.  Owner's decision, 21 Aug 2026: the API is
  reached at the port, not through an ssh tunnel (8, posture B reversed).

  NO SshWasAbsent GUARD, and that is the difference from ApplySshFirewall
  above.  That one refuses unless SD installed the ssh server itself, because
  SD does not reconfigure an ssh server it did not install (5.9) - the rule is
  about somebody else's software.  THIS RULE IS SD'S OWN, for SD's own port,
  created by api-firewall.ps1 and removed by it on uninstall, so there is no
  pre-existing configuration to respect and nothing to refuse.

  NO -Port EITHER, so the rule is for api-firewall.ps1's default, which is the
  same 4243 that gplbld/stage.py's SD_CONF template sets.  An administrator who
  changes APIPORT afterwards has to re-run the script with -Port; the script's
  own header says why it does not read sd.conf to find out. }
function ApplyApiFirewall: String;
var
  Code: Integer;
  Ps, Args: String;
  Wanted: Boolean;
begin
  Result := '';

  { 25 Aug 26 - NO RULE AT ALL ON A STAND-ALONE INSTALL, not even a -Restrict
    one.  The stand-alone sd.conf carries no APIPORT, so SD binds no socket
    (gplsrc/sdwind.c, open_api_listener: port <= 0 returns "no listener").  A
    firewall rule for a port nothing is listening on would be a rule describing
    a service that does not exist - and the mode page tells the reader there is
    "no rule to open", which has to stay true.

    api-firewall.ps1 -Restrict is NOT harmless-and-tidy here for that reason:
    it would leave behind a rule naming port 4243 that the uninstaller then has
    to remove, on a system that never had the API. }
  { 30 Aug 26 - RE-KEYED FROM StandaloneChosen TO THE API BOX ITSELF, AND THE
    EXIT NOW MEANS THE SAME THING IT ALWAYS DID.  PRE_RELEASE_FIXES 75.  An
    unticked box no longer means "the listener exists but keep others off it";
    it means SD installs the no-listener sd.conf and opens no socket at all, so
    there is again no service for a rule to describe - which is exactly what the
    comment above says about writing one.

    ***THE COST THIS USED TO CARRY IS PAID OFF, 30 Aug 2026 - PRE_RELEASE 75.***
    There used to be a third state - listener up, firewall restricted - which is
    what a local application talking to the API on 127.0.0.1 relied on, and
    collapsing the box to "provide it or do not" took it away: a local-only
    consumer had to tick the box, and ticking it also opened 4243 to the
    network.  The child task apiremote\apinetwork restores it, on the same
    parent/child shape already ruled for ssh.

    THE OWNER'S RULING IS UNTOUCHED.  "The api box unchecked should mean not
    provide the service at all" is still exactly what the Exit below does; what
    changed is only the SCOPE applied when the service IS provided. }
  if not ApiWanted then
    Exit;

  { 30 Aug 26 - THE SCOPE FOLLOWS THE CHILD, NOT THE PARENT, and that one line
    is the whole of 75's fix.  Parent alone -> -Restrict, this computer only.
    Parent and child -> -Open.  It was ApiWanted, which could only ever be true
    here, so the else arm was dead and every install that provided the API
    opened it to the network. }
  Wanted := ApiNetworkWanted;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
          ExpandConstant('{app}\api-firewall.ps1') + '"';
  if Wanted then
    Args := Args + ' -Open'
  else
    Args := Args + ' -Restrict';

  if not Exec(Ps, Args, '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'Who may reach the SD Core API could NOT be set: the script did not run. ' +
              'No firewall rule was created, so other computers cannot reach port 4243.' + #13#10#13#10;
    Exit;
  end;

  if Code = 0 then
  begin
    if Wanted then
      Result := 'Other computers on your network CAN now connect to the SD Core API on port 4243. ' +
                'They still need an SD Core account with a password and API access.' + #13#10#13#10
    else
      { 30 Aug 26 - THIS ARM WAS UNREACHABLE UNTIL NOW.  PRE_RELEASE_FIXES 75:
        Wanted was ApiWanted, which is always true by the time we get here, so
        every install that provided the API took the branch above.  It is the
        DEFAULT arm now - parent ticked, child not - so its wording matters.

        AND IT NAMES THE VERB FIRST, not the script.  remote.api shipped with
        entry 78; telling the reader to run a PowerShell file when SD has a
        command for it is exactly the staleness 77 was filed for.  The script
        stays as the second line because remote.api needs SD running and an
        administrator signed in, and this text is read at install time. }
      Result := 'The SD Core API can be reached FROM THIS COMPUTER ONLY. To let other computers ' +
                'connect later, sign in to SD Core as an administrator and run:' + #13#10#13#10 +
                '    remote.api on' + #13#10#13#10 +
                'or, from an elevated prompt:' + #13#10#13#10 +
                '    powershell -File "' + ExpandConstant('{app}') + '\api-firewall.ps1" -Open' + #13#10#13#10;
  end
  else
    Result := 'Setting who may reach the SD Core API FAILED, so no rule was created and other ' +
              'computers cannot reach port 4243. Run this from an elevated prompt to see why:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\api-firewall.ps1" -Open' + #13#10#13#10;
end;

{ What happened to the ssh server, judged from the state of the machine rather
  than from an exit code.

  FROM STATE, DELIBERATELY.  install-ssh.ps1 is a [Run] entry and a [Run] entry
  discards its exit code - a comment in this file claimed otherwise for months.
  Reading the machine is better than fixing that would have been: it answers the
  same way whether the capability was installed just now, was already there, or
  failed, and it cannot drift from what the user will actually experience.

  THE FAILURE BRANCH IS THE ONE THAT MATTERS.  While ssh was optional, no ssh
  meant the user had declined it.  It is now the state a blocked Features on
  Demand download leaves behind, and in it every account CREATE.ACCOUNT makes is
  denied the console and Remote Desktop with no ssh to fall back on - so it must
  be said in as many words rather than left to be discovered one account later. }
function SshReport: String;
begin
  { 25 Aug 26 - ON A STAND-ALONE INSTALL THIS IS THE ONLY PARAGRAPH ABOUT ssh,
    and it says what was NOT done rather than reporting an outcome.

    IT HAS TO BE SAID SOMEWHERE.  The three branches below all describe an ssh
    server SD installed or found; every one of them is false here, and saying
    nothing at all would leave a reader who half-remembers the disclosure page
    wondering whether the ssh step failed silently.  What was not done, and
    what that costs them, is the useful thing to close on.

    IT ALSO NAMES THE WAY OUT.  Reinstalling is the only route to a full
    system, and it is better read here - once, at the end, while they still
    have the installer - than discovered later. }
  { 30 Aug 26 - RE-KEYED FROM StandaloneChosen.  PRE_RELEASE_FIXES 67 and 75.
    The reader who declined the ssh server gets this instead of the old
    stand-alone paragraph, and it says the same operational things because they
    are the same install - which is the owner's whole argument for removing the
    mode.  What has gone from it is the claim that the decision is irreversible:
    ticking the box on a later run of this installer is now all it takes,
    because the ssh boxes read machine state rather than a marker. }
  if not SshServerPresentAfterwards then
  begin
    { 1 Sep 26 - PRE_RELEASE_FIXES 124.  This branch is SshWasAbsent AND NOT
      SshServerWanted (SshServerPresentAfterwards = (not SshWasAbsent) or
      SshServerWanted), so "you did not ask" is always right here - the
      ticked-but-download-failed case is the sshd.exe-missing branch below.  What
      WAS wrong is "ssh and nothing else, nobody can sign in": false when the API
      is provided, so the "who can sign in" line is conditioned on ApiWanted. }
    Result := 'NO ssh server was installed, because you did not ask for one. No ssh ' +
              'configuration was changed and no ssh port was opened. scp and sftp are ' +
              'unaffected on this computer.' + #13#10#13#10;

    { 02 Sep 26 - ApiListenerAfterwards, NOT ApiWanted.  PRE_RELEASE 89 Defect
      A hid the box on a tree that already has sd.conf, and a hidden task reads
      as not selected - so this would have promised "no API" over a preserved
      configuration that runs one. }
    if ApiListenerAfterwards then
      Result := Result +
                'Accounts you gave API access can still sign in over the SD Core API. ssh is ' +
                'the interactive way in; to add it, install OpenSSH Server and run this ' +
                'installer again, ticking the ssh boxes.' + #13#10#13#10
    else
      Result := Result +
                'With no ssh server and no API, the accounts you create have no way to sign in ' +
                'yet. Administrators still use SD Core by typing "sd" at an elevated prompt, ' +
                'including creating and managing accounts. To let accounts sign in, install ' +
                'OpenSSH Server or provide the API, and run this installer again.' + #13#10#13#10;
    Exit;
  end;

  { 30 Aug 26 - THIS TEXT WAS TRUE UNTIL TODAY AND IS NOW HALF FALSE.
    PRE_RELEASE_FIXES 76.  It promised that SD "left both its configuration and
    its firewall rule exactly as they were" on a machine that already had ssh.
    The configuration half still holds - nothing here writes sshd_config for a
    server SD did not install - but the firewall half no longer does, because
    the owner's ruling of 30 Aug 2026 is that the scope choice must be offered
    in exactly this case.  The box is pre-set from the rule's current scope, so
    a reader who touched nothing still changed nothing; saying so is the honest
    version, and claiming SD kept its hands off the rule would now be a lie. }
  if not SshWasAbsent then
  begin
    Result := 'This machine already had an OpenSSH server. SD Core did not install, restart or ' +
              'reconfigure one, and it did not change its configuration. Who may reach it ' +
              'was set from the ssh box on the tasks page, which started out matching this ' +
              'computer''s existing firewall rule - so if you left it alone, nothing about ' +
              'that changed either. SD Core accounts sign in over ssh, so check that yours will ' +
              'accept them.' + #13#10#13#10;
    Exit;
  end;

  if not FileExists(ExpandConstant('{sys}\OpenSSH\sshd.exe')) then
  begin
    Result := 'The OpenSSH server could NOT be installed. Windows downloads it on demand, so ' +
              'this is usually a policy that blocks optional features, a metered connection, ' +
              'or no connection at all.' + #13#10#13#10 +
              'SD Core itself is installed and works; administrators use it by typing "sd" at ' +
              'an elevated prompt. You asked for the ssh server, so the accounts you create ' +
              'are set to sign in over ssh - but until the server is there they cannot.';
    { 02 Sep 26 - ApiListenerAfterwards, for the reason given at the branch
      above: on a preserved tree the box is hidden and its answer is not the
      one to report. }
    if ApiListenerAfterwards then
      Result := Result + ' Accounts you also gave API access can use the API meanwhile.';
    Result := Result + #13#10#13#10 +
              'Put the server right from an elevated PowerShell prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\install-ssh.ps1"' + #13#10#13#10;
    Exit;
  end;

  if not SshServiceRegistered then
  begin
    Result := 'OpenSSH Server was installed and NEEDS A RESTART before it will run. This is ' +
              'normal and is Windows'' doing, not SD Core''s - SD Core itself needs no restart.' + #13#10#13#10 +
              'Until you restart, the ssh service does not exist, so no SD Core account except ' +
              'your own can sign in.' + #13#10#13#10;
    Exit;
  end;

  Result := 'OpenSSH Server was installed and is running.' + #13#10#13#10;
end;

{ GIVE THE INSTALLING USER AN SD ACCOUNT.  Without this SD installs perfectly
  and then refuses the person who installed it: every SD account brings its own
  Windows account and theirs existed first, so "sd" answers "Account DON not in
  register" (PROJECT_STATUS.md 7 step 1f).

  FROM [Code] AT ssPostInstall, NOT FROM [Run], AND THAT IS THE WHOLE TRICK.
  The step needs an elevated token - it reaches SDSYS through sd -internal -
  and this runs with Setup's own.  The SDSYS password step that used to live at
  the bottom of this file was a "postinstall" checkbox, which Inno runs as the
  ORIGINAL user, and that is one of the three reasons it never worked.  The
  script handles the other two, starting a server and keeping its output.

  Returns the script's exit code, or -1 if it could not be run at all. }
{ BRING AN UPGRADED INSTALL'S DICTIONARIES UP TO THE RELEASE.

  WHY THE DICTIONARIES ARE BUILT AT INSTALL RATHER THAN SHIPPED.  Owner,
  25 Aug 2026: this repository holds no binary bits, and a dictionary is more
  efficient as a DYNAMIC file - so the dictionaries are created and loaded
  during the install.  gplbld\FILES_DICTS is the tracked source, 76 records,
  and gpl.bp\WRITE_INSTALL_DICTS is what turns it into dictionaries.

  A FIRST INSTALL HAS NOTHING TO DO HERE and this returns at once.  It copies
  the whole staged tree, whose dictionaries the BUILD's own bootstrap already
  wrote.  An upgrade deliberately preserves the user's data tree - dictionaries
  included, because they live inside it - so without this step a release that
  edited FILES_DICTS would never reach an upgraded machine, and a field would
  resolve on a fresh install and not on an upgraded one.

  IT MERGES RATHER THAN REPLACING, which is why it is that program and not a
  file copy: WRITE_INSTALL_DICTS writes one record at a time and clears
  nothing, so a dictionary item an administrator added survives.  That is
  UPDATE.ACCOUNT's shape, which is already the ruling for VOC.

  ORDERING.  After the four ACL steps above, deliberately: each of them grants
  BUILTIN\Administrators full control on the path it locks, so an elevated
  process can still write, and running after them means this never widens
  anything they have just narrowed.  Before AdoptAccount because both start a
  server and each stops one only if it started it, so the cheaper property is
  that neither depends on the other.

  ELEVATED, AND THEREFORE HERE RATHER THAN IN the Run section: the script
  reaches SDSYS through sd -internal, which needs Setup's own token.  The same
  three faults AdoptAccount's header lists apply, and upgrade-dicts.ps1 handles
  them the same way.

  Returns '' when it worked or had nothing to do, and a paragraph for the
  closing box when it did not. }
function RefreshDictionaries: String;
var
  Code: Integer;
  Ps: String;
begin
  Result := '';
  if DataTreeWasAbsent then Exit;

  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  ExpandConstant('{app}\upgrade-dicts.ps1') + '" -AppDir "' +
                  ExpandConstant('{app}') + '" -DataDir "' +
                  ExpandConstant('{#DataDir}') + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'The dictionary update step could not be started, so this ' +
              'upgrade kept the dictionaries it already had. SD Core works; a ' +
              'field added by this release may not be recognised. Run ' +
              'upgrade-dicts.ps1 from the SD Core program folder, as an ' +
              'administrator.' + #13#10#13#10;
    Exit;
  end;

  { JUDGED ON THE SCRIPT'S OWN EXIT CODES, which its header lists.  Anything
    that is not one of the three named failures is still a failure - a case
    that fell through silently is how a step of this shape hides. }
  case Code of
    0: ;
    3: Result := 'SD Core would not start during the upgrade, so the dictionaries ' +
                 'were not updated. Everything else installed. Run ' +
                 'upgrade-dicts.ps1 from the SD Core program folder, as an ' +
                 'administrator, once SD Core is running.' + #13#10#13#10;
    { DO NOT LET A #13 START A LINE, even in the middle of an expression: ISPP
      reads a leading "#" as a preprocessor directive and answers "Unknown
      preprocessor directive", naming a line that looks like ordinary Pascal.
      Both branches below wrapped that way when they were written and were
      caught by compiling the section rather than by reading it - which is the
      same fault that cost a cycle on 19 Aug 2026, and the reason cycle.ps1
      lints for it before it stages anything. }
    4: Result := 'This installer did not carry the dictionary definitions, so ' +
                 'the dictionaries were not updated. That is a fault in the ' +
                 'build rather than on this computer - please report it.' + #13#10#13#10;
  else
    Result := 'The dictionaries could not be brought up to date for this ' +
              'release, so this upgrade kept the ones it already had. SD Core ' +
              'works; a field added by this release may not be recognised. ' +
              'upgrade-dicts.log in the SD Core data folder says what happened.' + #13#10#13#10;
  end;
end;

(* 30 Aug 26 - THE '$standalone' MARKER AND WriteStandaloneMarker ARE GONE.
   PRE_RELEASE_FIXES 75.  The marker existed for one reader - CREATEA, which
   used it to refuse CREATE.ACCOUNT USER - and that refusal is removed with it,
   on the owner's ruling that it is redundant now the ssh server is a per-install
   choice answered per route rather than a mode.

   NOTHING IS LEFT TO CLEAN UP ON AN EXISTING SYSTEM.  A machine installed
   stand-alone before today still has the file; CREATEA no longer reads it, and
   no ship list has ever named it, so the generated upgrade.iss will not delete
   it either.  It becomes an inert text file in SDSYS whose own contents explain
   what it used to do - which is the reason it was written for a human in the
   first place, and is a better outcome than an upgrade silently removing a file
   somebody may have noticed. *)

function AdoptAccount: Integer;
var
  Code: Integer;
  Ps: String;
begin
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  { -AppDir IS PASSED, NOT LEFT TO THE SCRIPT.  Its default used to be
    $PSScriptRoot, which comes out EMPTY in a param default when the script is
    an advanced one with a mandatory parameter - so the step failed on a real
    install with nothing readable.  Setup knows where it put the files; say so.
    Do not start a line in this file with a square bracket, even in a comment:
    ISCC scans for section tags first and answers "Invalid section tag". }
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  ExpandConstant('{app}\adopt-account.ps1') + '" -User "' +
                  ExpandConstant('{username}') + '" -AppDir "' +
                  ExpandConstant('{app}') + '" -DataDir "' +
                  ExpandConstant('{#DataDir}') + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := -1;
    Exit;
  end;
  Result := Code;
end;

{ AND THE INSTALL ENDS IN AN SD SESSION, WHICH IS HOW THE PASSWORD IS TAKEN.
  Owner's decision, 21 Aug 2026: the installing user's password is collected by
  leaving them in SD at the end of the install, not by an installer password
  page.  ADOPT creates no Windows user and sets no password, so the account
  AdoptAccount has just made has no credential, and LOGIN's require.credential
  asks for one before the prompt appears.  This function only opens the door;
  the asking is SD's.

  ELEVATED, AND THEREFORE HERE RATHER THAN AS A "postinstall" [Run] CHECKBOX,
  which is what the approved plan called for.  The gravestone in the [Run]
  section above is why it is not.  Three things killed the old SDSYS password
  step; a postinstall checkbox fixes only the third:

    1. sd -internal needed a running server.  Answered - [Run] installs and
       starts the service before this, and adopt-account.ps1 stops a server
       only if it started that server itself.
    2. Inno logs a postinstall entry as "Run as: Original user", so it runs on
       the UNELEVATED token.  THIS ONE IS STILL FATAL AND IS THE WHOLE REASON
       FOR THE DIFFERENT SHAPE.  That token does not carry sdusers until the
       user signs out and back in, so it cannot open the data tree at all; and
       SecureCredStore has just locked $cred to SYSTEM and Administrators, so
       even if it could, !CRED_SET could not write the credential.  Setup's own
       token carries Administrators and both ACLs grant it.
    3. "nowait" meant the console vanished before anything could be read.
       SW_SHOW is the answer to that, and the ewNoWait note below says why
       not waiting is not the same fault twice.

  SD's own permission model needs no elevation for this - setting your OWN
  password takes the "own" branch in SET_ACC_PASSWORD and never reaches the
  administrator test - so what elevation buys is those two file ACLs and
  nothing else.  An elevated session still lands in the user's own account:
  the case that sent an elevated session to SDSYS was deleted from LOGIN on
  15 Aug 2026.

  A NEW CONSOLE, AND THAT IS FREE.  Setup is a GUI process with no console of
  its own, so Windows gives sd.exe one, and SW_SHOW makes it visible.

  ewNoWait, AND IT IS NOT THE "nowait" THAT KILLED THE OLD STEP.  That one hid
  a console for a command which exited at once, so the error vanished before
  anybody could read it.  This leaves a VISIBLE window running an INTERACTIVE
  session that stays until the person quits it - which is the owner's
  instruction in its own words: the password is collected "by leaving them in
  SD at the end of the install".  Waiting would instead hold the wizard open
  behind a prompt they have to know to type OFF at.

  CALLED AFTER THE CLOSING DIALOG, so the two do not compete: a modal box with
  focus while SD is asking for a password is how a password gets typed into the
  wrong window.

  A PROCEDURE, NOT A FUNCTION, and that is the honest shape.  Exec would answer
  whether the process STARTED, and nothing here can learn more than that - SD
  outlives this call, so whether a password was set is unknowable from Setup.
  The dialog therefore says what is about to be offered and how to get back to
  it, and there is no result worth returning. }
procedure RunFinishingStep;
var
  Code: Integer;
  Args: String;
begin
  { REWRITTEN 22 Aug 2026, owner: "put them both in one script, call sd for the
    password and then move on to the post validation", and put both AFTER the
    installer window has closed.

    THIS USED TO Exec sd.exe DIRECTLY, from ssPostInstall.  Two faults came of
    that on a real install: the wizard stayed on screen behind the SD window,
    and the CHECK was a separate Finished-page tickbox, so ONE ACTION ASKED THE
    USER TWICE.  Setup now launches ONE script which does the password step and
    the check in order, in ONE window.

    -QUIET STILL, and it lives in finish-install.ps1 now rather than here.

    ELEVATED, AND THAT IS NOT A CHOICE.  The password step needs Setup's token:
    the gravestone in the Run section records why - an unelevated token does not
    carry sdusers until the user signs out, so it cannot open the data tree, and
    SecureCredStore has just locked $cred to SYSTEM and Administrators.  The
    check therefore runs elevated too, which is a REAL TRADE and is written up
    in finish-install.ps1's header: it answers the database question about the
    ADMINISTRATOR token, says so twice on screen, and the Start Menu shortcut is
    the run that answers it properly after a sign-out.

    ewNoWait, so Setup does not sit behind the window it just opened.  The
    script itself waits on SD - it can afford to, nothing is holding it open but
    the user, and that wait is what sequences the two steps.

    A PROCEDURE, NOT A FUNCTION.  Exec answers whether the process STARTED and
    nothing here can learn more: the script outlives this call, so whether a
    password was set is unknowable from Setup. }
  { -User IS PASSED, NOT LEFT TO $env:USERNAME.  Setup knows who is installing;
    the script would otherwise be guessing from its own process, and it uses the
    name to look for a credential afterwards.  Same rule as -AppDir, which
    adopt-account.ps1 records costing a real install when it was defaulted. }
  Args := '-NoProfile -ExecutionPolicy Bypass -File "' +
          ExpandConstant('{app}\finish-install.ps1') + '" -AppDir "' +
          ExpandConstant('{app}') + '" -User "' +
          ExpandConstant('{username}') + '"';
  if PasswordStepWanted then
    Args := Args + ' -WithPassword';

  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
              Args, ExpandConstant('{#DataDir}'), SW_SHOW,
              ewNoWait, Code) then
    { Not worth a message box - there is no wizard left to put one on, and the
      user has just been told to type "sd", which meets the same fault. }
    Log('finish-install.ps1 could not be launched');
end;

{ AFTER THE WIZARD HAS GONE, WHICH IS THE WHOLE POINT OF PUTTING IT HERE.
  Owner's instruction, 22 Aug 2026.  DeinitializeSetup runs as Setup terminates,
  with the wizard form already destroyed and Setup's ELEVATED token still held -
  the only hook that has both.  ssPostInstall has the token but runs with the
  wizard still on screen, and a postinstall Run entry runs after the window but
  on the UNELEVATED token, which the password step cannot use.

  IT FIRES ON A CANCELLED INSTALL TOO, hence the flag.  DeinitializeSetup is
  called however Setup ends - including when the user cancels on the first page
  - so without InstallReachedPostInstall this would open an SD session on a
  machine where nothing was installed. }
procedure DeinitializeSetup;
begin
  (* 23 Aug 2026 - "not WizardSilent" SHOULD NOW BE UNREACHABLE: InitializeSetup
     refuses a silent install outright, because SD does not support unattended
     installation (owner's ruling, same day).  It is kept as a second line of
     defence rather than tidied away, since what it guards is a password prompt
     opening with nobody to answer it - the exact fault that ruling came out of. *)
  if InstallReachedPostInstall and not WizardSilent then
    RunFinishingStep;
end;

{ LOCK THE SHELL PERMISSION LIST, and return what to tell the user if it did
  not happen.  PROJECT_STATUS.md 7 step 7.

  WHAT IT PROTECTS.  SDSYS os.users names the accounts allowed SH, one record
  per account.  CPROC reads it from the USER'S OWN process when they type SH,
  so ordinary users must be able to READ it - which is the difference from the
  credential store, where they get nothing at all.  What they must never have
  is WRITE: a user who can add their own name grants themselves a shell.

  SO THE ACL IS THE ENTIRE CONTROL, exactly as it is for $CRED, and it fails
  the same way if this step does not run - silently, with the list writable by
  the people it exists to restrain.  That is why this is here and not in [Run]:
  the exit code is checked.

  TWO OBJECTS, TWO CALLS.  The dictionary is locked as well.  It enforces
  nothing - CPROC reads the flags positionally, rec<1> and rec<2> - but an
  administrator reads the list THROUGH that dictionary, and a user able to
  redefine SH to point at another field could make LIST OS.USERS show
  something other than the truth.  Called once per path rather than passing
  both, because -File binds a comma-joined argument in ways that are worth not
  depending on.

  IT MUST RUN AFTER THE DATA-TREE icacls, like the credential store, and
  ssPostInstall is after the whole [Run] section. }
{ Locking one object, so SecureOsUsers can call it twice.  A separate function
  because Inno's Pascal Script has NO NESTED FUNCTIONS - declaring one inside
  another is "'BEGIN' expected" at the inner declaration, which does not name
  the cause. }
function LockOsUsersPath(Ps, Script, Target: String; var Code: Integer): Boolean;
begin
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" -Path "' + Target + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := (Code = 0);
end;

function SecureOsUsers: String;
var
  Code: Integer;
  Ps, Script, Store, Dict, Failed: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-osusers.ps1');
  Store := ExpandConstant('{#DataDir}\sdsys\os.users');
  Dict := ExpandConstant('{#DataDir}\sdsys\os.users.dic');

  Failed := '';
  if not LockOsUsersPath(Ps, Script, Store, Code) then
    Failed := Store
  else if not LockOsUsersPath(Ps, Script, Dict, Code) then
    Failed := Dict;

  if Failed = '' then
    Exit;

  { NAMED, NOT BURIED, for the same reason the credential store is: a list that
    anyone can edit is not a permission list, and nothing else in the install
    would reveal it. }
  Result := 'The shell permission list was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD Core user can add themselves to it and obtain a command shell. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Store + '"' + #13#10 +
            '    powershell -File "' + Script + '" -Path "' + Dict + '"' + #13#10#13#10;
end;

{ LOCK THE ACCOUNT DIRECTORIES.  PROJECT_STATUS.md section 8, "the B work".

  THE HOLE: the data tree grants sdusers Modify with (OI)(CI), so every account
  directory inherits it and any SD user can read and rewrite any other
  account's files outside SD.  Measured on the 16:54:55 install: from an
  ordinary session, listing another account's directory returned 6 entries and
  writing into it was allowed.

  SD ALREADY REFUSES THAT SESSION, so this aligns the file layer with the rule
  CPROC has enforced since 14 Aug 2026 rather than inventing a new one - LOGTO
  into that account answered "User not allowed in requested account" in the
  same measurement.

  TWO SCRIPTS, AND THE ORDER MATTERS.  secure-accounts.ps1 does the CONTAINER:
  it takes sdusers' inheritable Modify off user_accounts and leaves CREATOR
  OWNER inheritable, which is what lets CREATE.ACCOUNT populate a directory it
  has just made.  secure-account-dirs.ps1 then stamps each EXISTING account
  with its own sdu_<name>.  Container first: the second is pointless while the
  first is still handing out Modify to everybody.

  AFTER AdoptAccount, deliberately.  Adopt is what creates the installing
  user's own account, and running after it means that account is stamped by
  this step on the very install that creates it, rather than waiting for the
  next one.

  NEW accounts are stamped by CREATE.ACCOUNT itself (CREATEA's
  secure.account.dir), so this step is for the ones already on disk - which is
  why it runs unconditionally on every install rather than only on a fresh
  one. }
function SecureAccountDirs: String;
var
  Code: Integer;
  Ps, Container, PerAccount, Root: String;
  ContainerOk, PerAccountOk: Boolean;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Container := ExpandConstant('{app}\secure-accounts.ps1');
  PerAccount := ExpandConstant('{app}\secure-account-dirs.ps1');
  Root := ExpandConstant('{#DataDir}\user_accounts');

  ContainerOk := Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                      Container + '" -Path "' + Root + '"',
                      '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);

  PerAccountOk := False;
  if ContainerOk then
    PerAccountOk := Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                         PerAccount + '" -Root "' + Root + '"',
                         '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);

  if ContainerOk and PerAccountOk then
    Exit;

  { NAMED, NOT BURIED, like the credential store and the shell list: an ACL
    that is the whole of a control fails silently, and nothing else in the
    install would reveal it. }
  Result := 'The account directories were NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until they are, any SD Core user can read and rewrite any other account''s ' +
            'files outside SD Core. Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Container + '" -Path "' + Root + '"' + #13#10 +
            '    powershell -File "' + PerAccount + '" -Root "' + Root + '"' + #13#10#13#10;
end;

{ LOCK THE GLOBAL CATALOGUE.  PROJECT_STATUS.md 8, UPSTREAM_FIXES.md 7.

  gcat holds the object code every session executes - $LOGIN among it, which
  CPROC calls for EVERY session - and the data tree grants sdusers Modify, so
  without this any SD user can replace a program that runs in everybody's
  session or delete one and stop the machine signing in.

  IT REUSES LockOsUsersPath, which is generic despite the name: one path, one
  script, one exit code.  A second copy of four lines would only be a second
  place to fix.

  THE BASIC HALF IS NOT ENOUGH ON ITS OWN, which is why this exists as well.
  CATALOG and DELCAT now test K$ADMINISTRATOR, but a gate in a program protects
  that program; the ACL protects the directory from everything, including code
  not yet written.  secure-gcat.ps1's header carries the consequence: global
  cataloguing now needs a genuinely ELEVATED session. }
{ LOCK THE BATCH COMMAND LIST.  PROJECT_STATUS.md 7 step 9.

  THE SAME CONTROL AS THE SHELL LIST ABOVE, on a different file and against a
  different escalation.  SDSYS batch.jobs names, per account, the commands that
  account may run from the command line - which is how a scheduled job runs
  anything at all now that LOGIN admits a listed command instead of demanding an
  elevated session.  LOGIN reads it from the USER'S OWN process, so ordinary
  users must be able to READ it and must never be able to WRITE it: a user who
  can add a line to their own record grants themselves the command line.

  IT REUSES secure-osusers.ps1, which takes -Path and is not specific to
  os.users.  A second script would be a second thing to keep true.

  WHY NOT IN THE VOC, where section 8 designed it: SDSYS voc is inside the data
  tree, which grants sdusers Modify - measured 22 Aug 2026 by writing a file
  into it from an ordinary token - and a VOC record cannot carry an ACL of its
  own.  Then the list would be decoration, which is what happened to $CRED.

  TWO OBJECTS, TWO CALLS, and the dictionary for the reason SecureOsUsers gives:
  an administrator reads the list THROUGH it. }
function SecureBatchJobs: String;
var
  Code: Integer;
  Ps, Script, Store, Dict, Failed: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-osusers.ps1');
  Store := ExpandConstant('{#DataDir}\sdsys\batch.jobs');
  Dict := ExpandConstant('{#DataDir}\sdsys\batch.jobs.dic');

  Failed := '';
  if not LockOsUsersPath(Ps, Script, Store, Code) then
    Failed := Store
  else if not LockOsUsersPath(Ps, Script, Dict, Code) then
    Failed := Dict;

  if Failed = '' then
    Exit;

  Result := 'The batch command list was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD Core user can add commands to their own record and run them ' +
            'from the command line.  Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Store + '"' + #13#10 +
            '    powershell -File "' + Script + '" -Path "' + Dict + '"' + #13#10#13#10;
end;

function SecureGcat: String;
var
  Code: Integer;
  Ps, Script, Target, Objects, Failed: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-gcat.ps1');
  Target := ExpandConstant('{#DataDir}\sdsys\gcat');
  Objects := ExpandConstant('{#DataDir}\sdsys\gpl.bp.out');

  { gpl.bp.out BESIDE gcat - owner's instruction, 18 Aug 2026.  It holds the
    compiled objects the global catalogue is loaded FROM, and it measured
    sdusers:(I)(OI)(CI)(M) on the 11:27:32 install after gcat was already
    locked.  On its own it is the weaker path - planting an object there does
    nothing until an administrator re-catalogues it - but that is a delay, not
    a barrier, and nothing writes it after an install except a gpl.bp
    recompile, which is elevated anyway.

    Called once per path, like SecureOsUsers: -File binds a comma-joined
    argument in ways that are worth not depending on. }
  Failed := '';
  if not LockOsUsersPath(Ps, Script, Target, Code) then
    Failed := Target
  else if not LockOsUsersPath(Ps, Script, Objects, Code) then
    Failed := Objects;

  if Failed = '' then
    Exit;

  { NAMED, NOT BURIED, like the credential store and the shell list: this ACL
    is the whole of a control and it fails silently if the step does not run. }
  Result := 'The global catalogue was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD Core user can replace the programs SD Core runs for every session. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Failed + '"' + #13#10#13#10;
end;

{ LOCK THE PCODE LIBRARY, and return what to tell the user if it did not
  happen.  PROJECT_STATUS.md 7 step 15.

  ONE LEVEL BELOW SecureGcat, AND THE PAIR IS THE POINT.  gcat decides which
  catalogued program runs for every session; <sysdir>\bin\pcode is the
  interpreter that runs it.  sysseg.c:189/193/279 reads that file whole into
  the shared segment at start-up and every session executes it through
  load_pcode() - so an SD user who could write it would run their own code in
  SDSYS's and an administrator's sessions from the next SD start.  It measured
  sdusers:(I)(OI)(CI)(M) on the 10:01:45 install, and the write was PROVED from
  an unelevated token rather than read off the ACE.

  ONE PATH, so no per-path loop: that directory holds only pcode and pcode.old.
  It must run AFTER the data-tree icacls, like every other lock here, or
  inheritance puts the Modify straight back. }
function SecurePcode: String;
var
  Code: Integer;
  Ps, Script, Target: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-pcode.ps1');
  Target := ExpandConstant('{#DataDir}\sdsys\bin');

  if LockOsUsersPath(Ps, Script, Target, Code) then
    Exit;

  { NAMED, NOT BURIED, like the global catalogue and the credential store: this
    ACL is the whole of a control and it fails silently if the step does not
    run. }
  Result := 'The pcode library was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD Core user can replace the interpreter every session runs. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Target + '"' + #13#10#13#10;
end;

{ LOCK THE SEVEN SDSYS SYSTEM DIRECTORIES NOTHING WRITES, and return what to
  tell the user if it did not happen.  PROJECT_STATUS.md 7 step 15, on the
  OWNER'S RULING of 24 Aug 2026.

  THE REST OF THE INHERITED sdusers:(M) LIST, minus the one that is used.
  Everything under the data tree inherits sdusers:(OI)(CI)(M) from the [Run]
  icacls above; SecureGcat and SecurePcode took two of those back, and this
  takes seven more.  accounts is the account register, $map and messages and
  newvoc are read by the interpreter and by CREATE.ACCOUNT, bp and cat are
  SDSYS's own program library and catalogue, and sd.conf is the configuration
  every sd.exe reads at start-up.  A user who can write them can rewrite who
  exists, what SDSYS runs, and how the server is configured.

  ***$ipc IS DELIBERATELY ABSENT AND MUST NOT BE ADDED.***  It is the eighth
  member of that list and the ONE an ordinary session was measured writing -
  every session modifies $ipc\%0, PHANTOM writes its command there (sd.c:55),
  APISRVR:214 opens it.  Locking it breaks every session and every phantom.
  The measurement is probe-syswrites.ps1: 15 verbs including the spooler and
  the saved-list family, plus a separate PHANTOM pass, on the 15:14:28 install
  of 24 Aug 2026.

  ***THAT NAME IS WRITTEN BARE, WITHOUT ITS DIRECTORY, DELIBERATELY, AND SO
  MUST ANY OTHER DEVELOPMENT SCRIPT NAMED IN THIS FILE.***  assert-current.ps1
  decides whether a file on its $neverShipped list really ships by scanning
  THIS FILE and stage.py for the name preceded by a quote or a path separator
  - the test that tells a ship list from a passing remark.  Prefixing that
  probe with its directory here put a development-only script back under the
  guard and made the whole tree report stale because a COMMENT mentioned it,
  measured 24 Aug 2026.  A script that really ships is quoted in stage.py's
  tuple and expanded from the app directory below; anything else gets a bare
  name.  (And that constant is not spelled out here either - Pascal comments
  do not nest, so ITS closing brace would end this one.)

  SEVEN CALLS, NOT ONE, and not a Pascal array either.  LockOsUsersPath is
  generic despite its name and passes ONE -Path, which is what SecureOsUsers
  and SecureGcat already do for their two: -File binds a comma-joined argument
  in ways that are worth not depending on.  No array is used anywhere in this
  file and this is not the place to find out how Inno's Pascal Script handles
  one.

  sd.conf IS A FILE AND THE OTHER SIX ARE DIRECTORIES.  The script branches on
  PSIsContainer because (OI) and (CI) are container-inherit flags and icacls
  REFUSES them on a file; nothing is needed here, but it is the reason this
  list may not be reordered into something that assumes all seven are alike.

  IT MUST RUN AFTER THE DATA-TREE icacls, like every other lock here, or
  inheritance puts the Modify straight back.  ssPostInstall is after the whole
  Run section, so that ordering is structural rather than a rule about where
  to put a line. }
function SecureSysdirs: String;
var
  Code: Integer;
  Ps, Script, Failed: String;
  Accounts, Map, Messages, Newvoc, Bp, Cat, Conf: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-sysdirs.ps1');

  Accounts := ExpandConstant('{#DataDir}\sdsys\accounts');
  Map      := ExpandConstant('{#DataDir}\sdsys\$map');
  Messages := ExpandConstant('{#DataDir}\sdsys\messages');
  Newvoc   := ExpandConstant('{#DataDir}\sdsys\newvoc');
  Bp       := ExpandConstant('{#DataDir}\sdsys\bp');
  Cat      := ExpandConstant('{#DataDir}\sdsys\cat');
  Conf     := ExpandConstant('{#DataDir}\sd.conf');

  Failed := '';
  if not LockOsUsersPath(Ps, Script, Accounts, Code) then
    Failed := Accounts
  else if not LockOsUsersPath(Ps, Script, Map, Code) then
    Failed := Map
  else if not LockOsUsersPath(Ps, Script, Messages, Code) then
    Failed := Messages
  else if not LockOsUsersPath(Ps, Script, Newvoc, Code) then
    Failed := Newvoc
  else if not LockOsUsersPath(Ps, Script, Bp, Code) then
    Failed := Bp
  else if not LockOsUsersPath(Ps, Script, Cat, Code) then
    Failed := Cat
  else if not LockOsUsersPath(Ps, Script, Conf, Code) then
    Failed := Conf;

  if Failed = '' then
    Exit;

  { NAMED, NOT BURIED, like the global catalogue and the credential store: this
    ACL is the whole of a control and it fails silently if the step does not
    run.  The path that failed is named because seven were attempted and the
    manual command below is only worth anything if it says which one. }
  Result := 'An SD Core system directory was NOT locked (code ' + IntToStr(Code) + '): ' +
            Failed + '. ' +
            'Until it is, any SD Core user can rewrite the account register, the system ' +
            'programs SDSYS runs, or the configuration SD Core reads at start-up. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Failed + '"' + #13#10#13#10;
end;

{ LOCK THE CREDENTIAL STORE, and return what to tell the user if it did not
  happen.  PROJECT_STATUS.md 7 step 6.

  WHAT IT PREVENTS IS WRITING, NOT READING.  $CRED holds a per-account salt
  and an Argon2 verifier, never a password.  The data tree grants sdusers
  Modify, and inherited onto the credential store that lets any SD user
  OVERWRITE another account's verifier with one derived from a password they
  chose, then authenticate through the API as that account - a straight
  privilege escalation, where reading an Argon2 verifier is worth little.
  It stays reachable by everything that needs it: API sessions are forked by
  sdwind, which runs as LocalSystem, and MODIFY.PASSWORD is an administration
  verb run from an elevated session.

  IT MUST RUN AFTER THE DATA-TREE icacls, or inheritance puts that Modify
  straight back.  ssPostInstall is after the whole Run section, so that
  ordering is structural here rather than a rule about where to put a line.

  THE PATH IS DOUBLE QUOTED, LIKE EVERY OTHER SCRIPT ARGUMENT IN THIS FILE.
  CORRECTED 17 Aug 2026, and the comment it replaces had been wrong since the
  step was written.  That comment said the path had to be SINGLE quoted
  because "PowerShell EXPANDS $CRED inside a double-quoted string", leaving
  -Path as ...\sdsys\ with the step reporting success.

  THAT IS TRUE OF -Command AND FALSE OF -File, AND THIS IS -File.  Measured
  17 Aug 2026, driving powershell.exe from a batch file so the command line
  reaches it as raw as Inno's does, with a probe script that printed its own
  argument:

    -File    -Path '...\sdsys\$CRED'   ->  ['...\sdsys\$CRED']  151 chars
    -File    -Path "...\sdsys\$CRED"   ->  [...\sdsys\$CRED]    149 chars
    -Command -Path "...\sdsys\$CRED"   ->  [...\sdsys\]         144 chars

  So -File never runs the argument through the expression parser: it neither
  expands $CRED nor strips single quotes, and the shipped single quotes
  arrived as part of the value.  Test-Path then failed and secure-cred.ps1
  exited 2 saying "does not exist - nothing secured" - correctly, on a path
  that really did not exist.  The escape the status file proposed instead,
  a backtick before the $, is wrong for the same reason: -File delivers the
  backtick literally too.

  AND THE EXIT CODE IS CHECKED, which is why this is here and not in Run.
  The step was copied from secure-audit.ps1, including its deliberate absence
  of a check - but that rationale does not carry across.  A missed audit ACL
  leaves an editable trail, which is the pre-16-Aug behaviour; a missed
  credential ACL leaves an escalation open, and it did, silently, for a whole
  session.  A Run entry discards the exit code (this file records the same
  mistake being made about the OpenSSH entry), so checking it means Exec. }
{ PUT EVERY NON-ADMINISTRATOR SD ACCOUNT BACK INTO sdsshonly, and return what
  to tell the user if it did not happen.  PRE_RELEASE_FIXES 135.

  WHY IT IS NEEDED AT ALL.  The uninstaller deletes sdsshonly outright, and a
  Windows local group takes its membership with it.  This install recreated the
  group and deny-logon.ps1 has just reapplied SeDenyInteractiveLogonRight and
  SeDenyRemoteInteractiveLogonRight to it - correctly, and to a group with
  NOBODY IN IT.  Without this step every account that was confined to ssh
  silently gets the console and Remote Desktop back, and the box below tells
  the reader their accounts are untouched while it is true of the data and
  false of the access.

  ***IT IS IN [Code] AND NOT [Run] FOR SecureCredStore's REASON***, written out
  where that one is: a Run entry discards the exit code, and this is a step
  whose silent failure is a privilege escalation rather than a degraded
  install.  Any non-zero is reported in the closing box.

  ***AFTER AdoptAccount, DELIBERATELY.***  Adopt is the install's own writer
  into the register, so running after it means the register this reads is the
  finished one.  The adopted user is an administrator - the installer required
  elevation to get here - so the script skips them by the same rule CREATEA
  uses, and the ordering costs nothing either way.

  IT READS THE REGISTER RATHER THAN ANY LOCAL GROUP, on the owner's ruling of
  2 Sep 2026, because the same repair has to work when SD is MOVED to a new
  computer and the only thing that arrives is the data tree.  The script's own
  header carries that reasoning. }
function RestoreSshOnly: String;
var
  Code: Integer;
  Ps, Script, Data: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\restore-sshonly.ps1');
  Data := ExpandConstant('{#DataDir}');

  if not FileExists(Script) then
  begin
    Result := 'The ssh-only confinement could NOT be restored: restore-sshonly.ps1 ' +
              'is not installed. Accounts that were confined to ssh can sign in at ' +
              'the console and over Remote Desktop until an administrator puts them ' +
              'back into the "sdsshonly" group.' + #13#10#13#10;
    Exit;
  end;

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" -DataDir "' + Data + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  { Exit 2 is "could not measure and did nothing" and exit 1 is "a repair
    failed"; both leave accounts unconfined, so both say the same thing to the
    reader and the code distinguishes them for whoever reads the log. }
  Result := 'The ssh-only confinement was NOT restored (code ' + IntToStr(Code) + '). ' +
            'Accounts SD Core created are meant to reach this computer only over ssh, ' +
            'and until this is put right they can also sign in at the console and over ' +
            'Remote Desktop. Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -DataDir "' + Data + '"' + #13#10#13#10;
end;

function SecureCredStore: String;
var
  Code: Integer;
  Ps, Script, Store: String;
begin
  Result := '';
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-cred.ps1');
  Store := ExpandConstant('{#DataDir}\sdsys\$cred');

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" -Path "' + Store + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  { NAMED, NOT BURIED.  Anything other than 0 means other SD users can still
    overwrite each other's stored credentials, so the one thing this must not
    do is finish quietly.  The recovery is the same script the installer
    itself ran, so the user gets the same code path rather than a hand-built
    icacls line that could grant something subtly different. }
  Result := 'The credential store was NOT locked (code ' + IntToStr(Code) + ').  Until it is, any SD Core ' +
            'user can overwrite another account''s stored password and then sign in as them. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Store + '"' + #13#10#13#10;
end;

{ ---------------------------------------------------------------------------
  The closing summary box
  --------------------------------------------------------------------------- }

{ SM_CYSCREEN for the overflow test below.  Inno exposes no screen metrics of
  its own and this is the only thing here that needs one. }
function GetSystemMetrics(nIndex: Integer): Integer;
  external 'GetSystemMetrics@user32.dll stdcall';

{ A CUSTOM FORM RATHER THAN MsgBox, BECAUSE MsgBox HAS NO WIDTH TO SET.
  Owner, 23 Aug 2026: "this dialog is very tall, can it be made wider and
  shorter?"  Windows sizes a message box itself and Inno exposes no control
  over it, so the only way to widen this one is to stop calling MsgBox.

  MEASURED BEFORE IT WAS BUILT, BECAUSE WIDENING ALONE DOES NOT DO IT.  The
  healthy-install text, Segoe UI 9pt, wrapped with TextRenderer.MeasureText:

      450px text column            675px tall   <- about what MsgBox chose
      800px text column            555px tall   <- widening buys 120px, 18%
      800px, blank lines collapsed 345px        <- the other 210px is spacing

  So the FIFTEEN BLANK SEPARATOR LINES cost more height than the narrow column
  does, and a wider MsgBox - if there were such a thing - would still have been
  tall.  This draws each paragraph as its own control with a SEVEN pixel gap in
  place of a fifteen pixel empty line, which is what actually makes it short.

  IT CHANGES NOT ONE WORD OF THE MESSAGE.  The split is on the blank lines the
  string already contains, so every fragment assembled above still reads the
  same and still concatenates the same way - the blank lines become layout
  instead of characters.  DO NOT "SIMPLIFY" THIS INTO A SINGLE MEMO: a memo
  renders those blank lines and the box goes straight back to being tall.

  THE WIDTH IS MEASURED, NOT CHOSEN.  On the owner's screen the MsgBox came out
  454x885 and the first attempt at this - ScaleX(820) - came out 1413x493,
  which he called "way too wide".  His instruction was halfway between the two,
  so ScaleX(542): measured 940x557 on the same screen.  Height is down 37% and
  the width is his.  Re-measure before changing it rather than nudging it.

  THE MEMO IS STILL HERE AS A FALLBACK, DELIBERATELY.  A label stack cannot
  scroll - Inno's scripting exposes no TScrollBox - so on a short screen, or an
  install unlucky enough to raise every warning above at once, the stack can be
  taller than the desktop with no way to reach the bottom.  When it does not
  fit this falls back to a scrolling memo holding the same string, which is no
  worse than what shipped before. }
procedure ShowSummaryBox(const Caption, Msg: String);
var
  F: TSetupForm;
  Host: TPanel;
  Memo: TNewMemo;
  Btn: TNewButton;
  Para: TNewStaticText;
  Rest, Chunk: String;
  P, Y, TextW, MargX, MargY, GapY, BtnH, MaxContentH: Integer;
begin
  MargX := ScaleX(14);
  MargY := ScaleY(14);
  GapY  := ScaleY(7);
  BtnH  := ScaleY(23);

  { The height passed here is a placeholder - the content sets it below, once
    the paragraphs have been laid out and their real heights are known. }
  F := CreateCustomForm(ScaleX(542), ScaleY(120), False, False);
  try
    F.Caption := Caption;
    TextW := F.ClientWidth - 2 * MargX;

    { SM_CYSCREEN is 1.  The 160 leaves the caption bar, the button row and a
      taskbar; the only job here is to notice a stack that will not fit. }
    MaxContentH := GetSystemMetrics(1) - ScaleY(160);

    Host := TPanel.Create(F);
    Host.Parent := F;
    Host.Left := MargX;
    Host.Top := MargY;
    Host.Width := TextW;
    Host.BevelOuter := bvNone;
    Host.Anchors := [akLeft, akTop, akRight, akBottom];

    Y := 0;
    Rest := Msg;
    while Rest <> '' do
    begin
      P := Pos(#13#10#13#10, Rest);
      if P = 0 then
      begin
        Chunk := Rest;
        Rest := '';
      end
      else
      begin
        Chunk := Copy(Rest, 1, P - 1);
        Rest := Copy(Rest, P + 4, Length(Rest));
      end;

      { Every optional fragment above ends with a blank line, so an empty
        chunk is the normal case rather than a malformed message. }
      if Trim(Chunk) = '' then
        Continue;

      Para := TNewStaticText.Create(F);
      Para.Parent := Host;
      Para.AutoSize := False;
      Para.WordWrap := True;
      Para.Left := 0;
      Para.Top := Y;
      Para.Width := TextW;
      Para.Caption := Chunk;
      Para.AdjustHeight();
      Y := Y + Para.Height + GapY;
    end;

    { No trailing gap under the last paragraph. }
    if Y > GapY then
      Y := Y - GapY;

    if Y > MaxContentH then
    begin
      Host.Free();
      Memo := TNewMemo.Create(F);
      Memo.Parent := F;
      Memo.Left := MargX;
      Memo.Top := MargY;
      Memo.Width := TextW;
      Memo.Height := MaxContentH;
      Memo.Anchors := [akLeft, akTop, akRight, akBottom];
      Memo.ReadOnly := True;
      Memo.WordWrap := True;
      Memo.ScrollBars := ssVertical;
      Memo.Text := Msg;
      Y := MaxContentH;
    end
    else
      Host.Height := Y;

    F.ClientHeight := MargY + Y + MargY + BtnH + MargY;

    Btn := TNewButton.Create(F);
    Btn.Parent := F;
    Btn.Caption := SetupMessage(msgButtonOK);
    Btn.Width := F.CalculateButtonWidth([Btn.Caption]);
    Btn.Height := BtnH;
    Btn.Left := F.ClientWidth - Btn.Width - MargX;
    Btn.Top := F.ClientHeight - BtnH - MargY;
    Btn.Anchors := [akRight, akBottom];
    Btn.ModalResult := mrOk;
    { Cancel as well as Default, so Esc and the X button close it like OK.
      There is nothing to decide here - the install has already happened. }
    Btn.Default := True;
    Btn.Cancel := True;

    F.ActiveControl := Btn;
    F.FlipAndCenterIfNeeded(True, WizardForm, False);
    F.ShowModal();
  finally
    F.Free();
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  SshLimit: String;
  SshFw: String;
  ApiFw: String;
  SshMsg: String;
  { 31 Aug 26 - PRE_RELEASE_FIXES 88.  What the closing box says INSTEAD of the
    ssh and API paragraphs on an upgrade.  Without it those paragraphs simply
    vanish and the reader is told nothing at all about the two settings the
    installer just declined to touch. }
  UpgMsg: String;
  RouteMsg: String;
  AdoptCode: Integer;
  AccountMsg: String;
  CredMsg: String;
  DenyMsg: String;
  OsuMsg: String;
  BjMsg: String;
  GcatMsg: String;
  PcodeMsg: String;
  SysdirMsg: String;
  AcctAclMsg: String;
  DictMsg: String;
  SshOnlyMsg: String;
  MarkerMsg: String;
begin
  if CurStep = ssPostInstall then
  begin
    { THE CREDENTIAL STORE GOES FIRST, ahead of even the firewall.  It is the
      only step here that closes a hole rather than configuring something, and
      AdoptAccount below is the install's own first writer into the data tree
      as an elevated process - so locking before it runs means the store is
      never open while an account is being made.  It needs no ordering against
      the Run section beyond being after it, which ssPostInstall guarantees. }
    CredMsg := SecureCredStore;

    { Beside the credential store and for the same reason: both are ACLs that
      are the whole of a control, and both fail silently if the step does not
      run.  Order between them does not matter - different files, no shared
      state - so it goes second simply because the escalation is the graver. }
    OsuMsg := SecureOsUsers;

    { Beside it, same control, different escalation: this one is the command
      line rather than the shell.  Order between them does not matter. }
    BjMsg := SecureBatchJobs;

    { Third of the three ACL steps, and the same reasoning: it closes a hole
      rather than configuring something, and it is silent if it does not run.
      Order between the three does not matter - different paths, no shared
      state. }
    GcatMsg := SecureGcat;

    { AND THE LEVEL BELOW IT, 23 Aug 2026, section 7 step 15.  Beside
      SecureGcat because they are the same control at two depths: gcat is
      which program runs, pcode is the interpreter that runs it.  Order
      between them does not matter - different paths, no shared state. }
    PcodeMsg := SecurePcode;

    { AND THE REST OF THE INHERITED Modify LIST, 24 Aug 2026, section 7 step
      15, on the owner's ruling.  Beside the two above because it is the same
      control over the remaining seven paths: gcat is which program runs,
      pcode is the interpreter that runs it, and these are the register, the
      system programs and the configuration.  Order between them does not
      matter - different paths, no shared state - and it goes last of the four
      only because it is the one whose list is longest to read.

      IT MUST STAY AFTER THE [Run] icacls, which ssPostInstall guarantees.
      $ipc is deliberately not in it; see the function. }
    SysdirMsg := SecureSysdirs;

    { AHEAD OF THE ssh STEPS BELOW because it is the one that confines the
      accounts rather than configuring the server, and it needs nothing from
      them - only that the sdsshonly group exists, which [Run] created.  It ran
      from [Run] until 17 Aug 2026, earlier than this, and the move is safe for
      the same reason: the rights are held by the GROUP, so nothing that has
      already happened depends on when they land. }
    DenyMsg := ApplyDenyLogon;

    { Before the silent-install exit below: the work happens either way, and it
      is only the message about it that a silent install skips.  The firewall
      goes first - it decides who can reach the server at all, and the two
      steps are independent, so the more fundamental one is done first. }
    { 31 Aug 26 - NOT ON AN UPGRADE.  PRE_RELEASE_FIXES 88.  The tasks page was
      never shown, so SshRemoteWanted is answering from whatever
      UsePreviousTasks restored - and ApplySshFirewall ALWAYS acts, -Open or
      -Restrict, so letting it run would move port 22 on the strength of a box
      nobody saw.  ***AND THE "SAFE" DIRECTION IS NOT SAFE EITHER***: a false
      SshRemoteWanted means -Restrict, which would silently CLOSE a port the
      site had deliberately opened.  Doing nothing is the ruling and is also
      the only answer that cannot be wrong.  remote.ssh on|off changes it. }
    if not TrueUpgrade then
    begin
      SshFw := ApplySshFirewall;
      SshMsg := SshReport;
    end
    else
    begin
      { SAY SO, rather than letting two paragraphs quietly disappear.  The
        commands are named because the ruling rests on them: "if the admin
        wants to make additional choices, we have given them the command line
        tools."  Run in SD as an administrator; each reports and changes
        nothing when given no keyword. }
      UpgMsg := 'YOUR ssh AND API SETTINGS WERE LEFT EXACTLY AS THEY WERE.' + #13#10#13#10 +
                'This is an upgrade, so SD Core did not ask about them again and has changed ' +
                'nothing about who may reach this machine.' + #13#10#13#10 +
                'FIRST, GIVE EACH ACCOUNT THE NEW COMMANDS. An upgrade replaces the ' +
                'shipped vocabulary but does not rebuild the one each account is using, so ' +
                'a command added by this release cannot be typed until you refresh it. ' +
                'Sign in and run this once in each account that needs them, SDSYS ' +
                'included - it takes no argument and keeps to that account''s tier:' + #13#10#13#10 +
                '    update.account' + #13#10#13#10 +
                'THEN, to change the settings above, in SDSYS as an administrator:' + #13#10#13#10 +
                '    remote.ssh on | off           who may reach ssh' + #13#10 +
                '    remote.api on | local | off   whether the API is provided, and to whom' + #13#10 +
                '    ssh.server install | remove   add or take away the OpenSSH server' + #13#10 +
                '    append.sd.path on | off       whether "sd" runs from any directory' + #13#10#13#10 +
                'Each of them reports the current setting, and changes nothing, when you ' +
                'give it no keyword.' + #13#10#13#10;
    end;

    { The other remote route, and the same reasoning about ordering: it decides
      who may reach the API port at all, and it depends on nothing above it.
      Owner's decision of 21 Aug 2026 makes this a route in its own right
      rather than something carried inside an ssh tunnel. }
    { 31 Aug 26 - AND THE SAME FOR THE API, for the same reason and with the
      same asymmetry: ApplyApiFirewall follows ApiNetworkWanted, which on a
      skipped page is the previous install's answer.  Running it would either
      re-open 4243 to the network unasked or shut a port the site had opened.
      remote.api on|local|off is the way to change it. }
    { 02 Sep 26 - "and ApiConfAbsent", PRE_RELEASE_FIXES 89 Defect A.  THE BOX
      IS NOW HIDDEN WHEN IT CANNOT ACT, AND THIS IS THE OTHER HALF OF THAT.
      A hidden task reads as NOT selected, so ApiNetworkWanted goes false and
      this call would have CLOSED port 4243 on every uninstall-then-reinstall -
      "visible but inert" becoming "invisible but active", which is the trap
      ShouldSkipPage's comment records, arriving by a second route.

      SO THE BOX AND THE FIREWALL STAND OR FALL TOGETHER, which also ends the
      half-acting shape 89 was filed for: the reader used to get a firewall
      change and no service change from one tick.  Where the box is not
      offered, the site's own rule is left exactly as it was and remote.api
      on|local|off is the way to change it. }
    if (not TrueUpgrade) and ApiConfAbsent then
      ApiFw := ApplyApiFirewall;

    { STRICTLY BEFORE ApplyAllowGroups.  That step points sshd at the sdssh
      group; this one creates it and seeds it from sdusers, which is the set
      that could ssh in a moment ago.  The other order hands sshd an empty
      group and locks every existing account out of the machine.  See the
      function's own comment. }
    RouteMsg := SyncRouteGroups;

    { 02 Sep 26 - "not TrueUpgrade", PRE_RELEASE_FIXES 118.  THE CLOSING BOX
      SAID ssh WAS LEFT ALONE AND THIS LINE HAD JUST REWRITTEN sshd_config.
      Measured on guest Windows 11 - Test 1: the box promises "YOUR ssh AND API
      SETTINGS WERE LEFT EXACTLY AS THEY WERE ... has changed nothing about who
      may reach this machine", and sshd_config's mtime moved at 15:18:45 with
      sshd.pid at 15:18:46 - so the file was rewritten and the service bounced
      inside the upgrade, dropping every live ssh session one dialog after the
      reader accepted a promise that it would not.

      THE FIREWALL HALF OF THE CLAIM WAS ALREADY TRUE: 88 gated
      ApplyApiFirewall directly above and ApplySshFirewall with it.  This step
      was simply not among them, which is the whole of the defect.

      SyncRouteGroups ABOVE IS DELIBERATELY LEFT UNGATED, and that is not an
      oversight to tidy later: sync-route-groups.ps1 seeds only the group IT
      created, so on a tree that already has sdssh it declines to seed and
      changes nobody's access.  Gating it would instead risk leaving the groups
      missing on a tree that lost them.  The ordering note above still holds -
      the seeding step must precede the AllowGroups write whenever both run. }
    if not TrueUpgrade then
      SshLimit := ApplyAllowGroups;

    { AN UPGRADE'S DICTIONARIES, and a no-op on a first install.  See the
      function: it is here rather than earlier because every ACL step above
      leaves Administrators full control, so nothing it writes is blocked, and
      running after them means it cannot re-open anything they narrowed. }
    DictMsg := RefreshDictionaries;

    { Same rule - an unattended install must still end with a usable account. }
    AdoptCode := AdoptAccount;

    { AFTER adopt, so the register this reads is the finished one.  See the
      function: this is the step that undoes an uninstall having deleted
      sdsshonly and taken every membership with it. }
    SshOnlyMsg := RestoreSshOnly;

    { 30 Aug 26 - THE MARKER STEP IS GONE.  PRE_RELEASE_FIXES 75.  MarkerMsg is
      kept as an empty string rather than being unpicked from the closing
      dialog, so the paragraph it used to contribute simply is not there. }
    MarkerMsg := '';

    { AFTER Adopt, so the account it has just made is stamped on this very
      install rather than on the next one.  See SecureAccountDirs. }
    AcctAclMsg := SecureAccountDirs;

    case AdoptCode of
      0: begin
           { DO NOT START A LINE WITH #13, even in the middle of an expression.
             ISPP reads a leading "#" as a preprocessor directive and answers
             "Unknown preprocessor directive" - the same class of trap as the
             square bracket the AdoptAccount comment warns about.  Every other
             line break in this file leaves the #13#10 at the END of a line for
             this reason. }
           { LOWER CASE, 23 Aug 2026, AND IT IS THE PRODUCT THAT MOVED RATHER
             THAN A PREFERENCE HERE.  Uppercase stood until the account-name
             half of 5.12 landed on 22 Aug: CREATEA downcases the register key
             and adopt-account.ps1 follows, so LIST ACCOUNTS answers "don".
             Naming it DON here sent the reader looking for an account spelled
             a way nothing in the product spells it.  The constant expanded
             below is the WINDOWS name and may be mixed case, which is why this
             folds rather than just dropping the call.

             AND DO NOT WRITE THAT CONSTANT'S NAME IN A BRACE COMMENT.  Pascal
             comments do not nest and the closing brace of the constant ENDS
             THE COMMENT, so the prose after it compiles as code - "Identifier
             expected", pointing at a line that looks like English.  Same class
             as the square bracket the AdoptAccount comment warns about, and it
             cost a compile here on 23 Aug 2026. }
           AccountMsg := 'You also have an SD Core account of your own, named ' +
                         Lowercase(ExpandConstant('{username}')) + '.' + #13#10#13#10;
           { REPLACED "Type sd to use it; there is no password to set, because
             Windows has already authenticated you."  The second half stopped
             being true on 21 Aug 2026 and was the wrong half of the truth even
             before: the console does not ask for a password and still does not,
             but the account needs one to be reachable from anywhere else.

             AND THE FIRST HALF CONTRADICTED THE SIGN-OUT PARAGRAPH ABOVE, which
             has always been the accurate one - an ordinary "sd" cannot open the
             database until this user's token carries sdusers.  The window below
             runs on SETUP's token, which carries Administrators, and that is
             the whole reason it can run now. }
           { 22 Aug 26 - IT NOW DESCRIBES TWO STEPS IN ONE WINDOW, because that
             is what happens.  The check used to be a tickbox on the Finished
             page, which asked the user a second time for one action; the
             tickbox is gone and both steps run from one script after this
             wizard closes.  Somebody who is not told that a window will open
             by itself, after the installer has apparently finished, has every
             reason to think something has gone wrong. }
           AccountMsg := AccountMsg +
                         'ONE WINDOW OPENS AFTER THIS INSTALLER CLOSES, and it does two ' +
                         'things in turn.' + #13#10#13#10;

           { 25 Aug 26 - WHAT THE PASSWORD IS FOR DEPENDS ON THE INSTALL, and
             the full-install sentence is false on a stand-alone system: there
             is no ssh and no API, so nothing reaches this account from another
             machine and a password buys nothing today.

             THE STEP IS STILL OFFERED, DELIBERATELY.  Skipping it would be a
             third behaviour to test and would leave $cred empty - the state
             that cost two sessions in Aug 2026 - for the sake of saving one
             prompt.  Saying plainly that it is optional here, and why somebody
             might still want it, is the honest version of the same saving. }
           { 30 Aug 26 - RE-KEYED FROM StandaloneChosen TO THE TWO BOXES THAT NOW
             DECIDE THE SAME THING.  PRE_RELEASE_FIXES 67 and 75.  The condition
             this branch cares about was never really "is this stand-alone" - it
             was "can anything reach this account from another machine", and that
             is now answered directly: no ssh server and no API listener. }
           { 02 Sep 26 - ApiListenerAfterwards, AND THIS IS THE SITE THAT MADE
             THE PREDICATE NECESSARY.  PRE_RELEASE 89 Defect A hides the API box
             on a tree that already has sd.conf; a hidden task reads as not
             selected, so this branch would have told the reader "Nothing can
             reach this account from another machine" on a machine still running
             the API.  A false claim of isolation is worse than the inert
             tickbox the ruling set out to remove. }
           if (not SshServerPresentAfterwards) and (not ApiListenerAfterwards) then
             AccountMsg := AccountMsg +
                         '    1. SD Core opens so you can give that account a password. A ' +
                         'PASSWORD IS REQUIRED even here: SD Core asks for one every time you ' +
                         'open the account and will not let a session go on without it. ' +
                         'Nothing can reach this account from another machine - no ssh server ' +
                         'was installed and the SD Core API is switched off - but that decides ' +
                         'WHO could use it, not whether it needs a password. It closes by ' +
                         'itself once you have set one.' + #13#10#13#10
           else
             AccountMsg := AccountMsg +
                         '    1. SD Core opens so you can give that account a password. A ' +
                         'PASSWORD IS REQUIRED: SD Core asks for one every time you open the ' +
                         'account and will not let a session go on without it. It is also what ' +
                         'reaches the account from ANOTHER machine, over ssh or the API. It ' +
                         'closes by itself once you have set it.' + #13#10#13#10;

           AccountMsg := AccountMsg +
                         '    2. The same window then checks the installation and tells ' +
                         'you what it found. It only reads; it changes nothing, and it ' +
                         'asks before it starts.' + #13#10#13#10 +
                         'The password step can run now, before you sign out, because it ' +
                         'borrows the installer''s rights. If you skip it, SD Core asks again ' +
                         'the first time you open the account.' + #13#10#13#10 +
      { 23 Aug 26 - WHAT SKIPPING ACTUALLY COSTS, owner's instruction the same
        day.  The paragraph above named ssh and the API and stopped there, which
        reads as "some features are unavailable".  It is stronger than that.

        02 Sep 26 - AND IT IS STRONGER AGAIN THAN THIS NOTE SAID.
        PRE_RELEASE_FIXES 130.  This paragraph used to finish "with no password
        the account is reachable ONLY from this machine, and only from an
        elevated session", and that was measured false on a guest: LOGIN asks
        for a credential on EVERY login and ends the session without one, so a
        passwordless account is reachable from nowhere at all - the elevated
        console included.  The reasoning it gave (5.6.2 gives local terminal
        access to administrators; $cred is locked to SYSTEM and Administrators)
        was sound about WHO could read the credential and said nothing about
        whether LOGIN would let the session proceed, which is the part that
        decides it.

        REMOTE DESKTOP IS NAMED because it is the case people get wrong: it
        feels like connecting from another computer and is not.  5.6.2 puts it
        with the physical console, on the administrator's side of the line. }
                         'A PASSWORD IS REQUIRED. Until this account has one it cannot be used ' +
                         'at all - not here at the keyboard, not over ssh, and not through the ' +
                         'SD Core API. Skipping the step does not leave you a keyboard-only ' +
                         'account; SD Core asks again the first time you open it, and will not ' +
                         'let a session go on without one.' + #13#10#13#10;
         end;
      { Lower case for the reason given at code 0 above. }
      2: AccountMsg := 'Your SD Core account, ' + Lowercase(ExpandConstant('{username}')) +
                       ', was already there and has been left alone.' + #13#10#13#10;
    else
      { Named rather than buried: without an account the person who just
        installed SD cannot use it at all, and the recovery is one command.

        THE RECOVERY IS THE SCRIPT, NOT THE VERB.  Owner's instruction,
        15 Aug 2026: ADOPT is not public.  This branch used to print
        "sd -internal CREATE.ACCOUNT USER <name> ADOPT", which is the one
        place in the product that documented it - contradicting the decision
        recorded in PROJECT_STATUS.md 7 step 1f, that K$INTERNAL is not a wall
        but stays undocumented, not in the changelog and not in this dialog.

        adopt-account.ps1 ships beside sd.exe and is what the installer itself
        ran, so naming it gives the user the SAME code path rather than a
        second, hand-driven one - and it keeps the verb out of sight. }
      { 29 Aug 26 - WHICH REFUSAL YOU GET DEPENDS ON HOW FAR ADOPT GOT, so it is
        no longer named.  This said "your account is not in the register", which
        is one of two messages now: PRE_RELEASE_FIXES 56 clause 2 removed
        LOGIN's administrator exemption from the sdusers gate, so a failed adopt
        that never reached the group is refused earlier, with "this user is not
        registered for SD use" instead.  THE RECOVERY IS UNCHANGED AND STILL
        WORKS - adopt-account.ps1 goes in through "sd -internal", which is
        exempt from that gate by design and is the reason this branch is a
        setback rather than a lockout. }
      AccountMsg := 'SD Core could NOT give you an account automatically (code ' +
                    IntToStr(AdoptCode) + '). Until one exists, "sd" will refuse you: ' +
                    'being a Windows administrator is not by itself an SD Core account, and ' +
                    'there is no exception for one. Put it right from an ELEVATED ' +
                    'PowerShell prompt:' + #13#10#13#10 +
                    '    powershell -File "' + ExpandConstant('{app}') + '\adopt-account.ps1" -User ' +
                    ExpandConstant('{username}') + #13#10#13#10 +
                    'What went wrong is recorded in ' + ExpandConstant('{#DataDir}') +
                    '\adopt-account.log' + #13#10#13#10;
    end;

    { /SUPPRESSMSGBOXES DOES NOT SUPPRESS THESE.  Measured 14 Aug 2026: a
      /VERYSILENT /SUPPRESSMSGBOXES install still stopped and waited for OK on
      both boxes below, so an unattended deployment would hang until somebody
      walked past.  WizardSilent is the test that actually works.  The
      uninstaller's confirmation is guarded separately by UninstallSilent,
      which is a different flag for the same reason. }
    if WizardSilent then
      Exit;

    { Group membership is fixed in the access token at logon, so the sdusers
      membership just granted is not in this user's token yet and the data
      tree will refuse them until they sign out and back in.  Saying so here
      is the difference between "SD is broken" and "sign out and back in".
      PROJECT_STATUS.md 6. }
    { THE VERB IS THE ONLY ANSWER THIS BOX GIVES.  It used to end by offering
      "net localgroup sdusers <name> /add" for somebody who already has a
      Windows account.  REMOVED 15 Aug 2026 (owner's decision) BECAUSE IT DOES
      NOT WORK: sdusers grants access to the data tree, but login needs a
      linked SD account, so a user added that way and nothing else is refused
      with "Account X not in register" - which is the exact symptom don himself
      had before step 1f (PROJECT_STATUS.md 7).  The door for an existing
      Windows account is ADOPT, and that stays undocumented deliberately.
      SD has accounts rather than accounts and users (docs/TCL_VERBS.md), so
      CREATE.ACCOUNT IS the account-creation interface. }
    { "SD is installed." USED TO BE THE FIRST LINE OF THE BODY and is now the
      window title instead - dropped 23 Aug 2026, owner, when the box stopped
      being a MsgBox.  A MsgBox is captioned "Setup" and cannot be told
      otherwise, so the body had to say it; a TSetupForm has a caption of its
      own and saying it twice wasted the first line of a box being shortened. }
    ShowSummaryBox('SD Core is installed',
           { EMPTY ON EVERY HEALTHY INSTALL, and first when it is not.  This is
             the one line in the box that reports a hole rather than a setting,
             so it is read before the sign-out instruction rather than after
             three paragraphs the reader already skimmed on the first page. }
           CredMsg +
           OsuMsg +
           BjMsg +
           GcatMsg +
           PcodeMsg +
           SysdirMsg +
           AcctAclMsg +
           { Empty on every first install and on every upgrade that worked.
             Beside the others because it reports something that did NOT
             happen, and the reader needs it before the settings. }
           DictMsg +
           { Beside CredMsg and for the same reason: both are empty on a healthy
             install, and both report a protection that is absent rather than a
             setting that is present. }
           DenyMsg +
           { And with DenyMsg, because they are the two halves of one control:
             DenyMsg reports that sdsshonly carries no deny rights, this reports
             that it has the rights and nobody in it.  Either way an account
             meant to be confined to ssh is not.  PRE_RELEASE_FIXES 135. }
           SshOnlyMsg +
           { And beside DenyMsg for the third time: empty unless the ssh and API
             groups could not be set up, in which case ssh is refused to
             everyone but administrators and the person needs to know now. }
           RouteMsg +
           'You have been added to the "sdusers" group, which is what grants ' +
           'access to the SD Core database.' + #13#10#13#10 +
           'Windows only applies group membership when you sign in, so you must ' +
           'SIGN OUT AND BACK IN (or restart) before SD Core will run. Until then it ' +
           'will report that it cannot open its files.' + #13#10#13#10 +
           { TRIMMED 16 Aug 2026, owner: "it is even longer".  Fair - the first
             page was added to move things EARLIER and then three paragraphs were
             added here as well, so the box grew rather than shrank.

             THE RULE FOR WHAT STAYS: this box says what the first page could not
             know in advance - what actually happened to ssh, to the firewall and
             to your account - plus the one instruction that is actionable right
             now, which is signing out.  Everything else the first page already
             said, and repeating it here is what made this unreadable.

             Removed: the "SD runs as a service and restarts itself" paragraph;
             the explanation of what LOGTO SDSYS does and why Windows asks for
             consent; the remote-control-tool passage; and the ADMINISTRATOR
             keyword.  The first page carries the service and what confining ssh
             to SD Core costs - PRE_RELEASE 129 retired the old four-word name
             for that, since the API is an independent way in and ssh was never
             the only one;
             the rest is reference material that belongs with the verb, not in a
             box somebody reads once.  The bare COMMANDS stayed, because they are
             the thing a reader comes back for.

             NEVER START A LINE WITH #13#10.  ISPP reads any line whose first
             non-blank character is "#" as a preprocessor directive, so a
             wrapped Pascal string constant becomes "Unknown preprocessor
             directive" and the compile aborts - line number and all, with
             nothing to say it is about string continuation.  Mid-line is fine,
             which is why every #13#10 in this box works.  Cost the eleventh
             session an ISCC run, 16 Aug 2026. }
           { The ssh pair goes here, above the account paragraph, because on a
             machine where the install failed or wants a restart it changes what
             the account advice MEANS - an account nobody can sign in to yet. }
           SshMsg +
           SshFw +
           ApiFw +
           { 31 Aug 26 - EMPTY ON A FIRST INSTALL, and it is the three above
             that are empty on an upgrade.  PRE_RELEASE_FIXES 88: exactly one
             of the two sets is ever non-empty. }
           UpgMsg +
           { 25 Aug 26 - EMPTY ON EVERY INSTALL THAT WENT RIGHT, and it sits
             beside the ssh pair for the same reason they do: if the marker did
             not get written, the account advice below is describing rules this
             machine will not actually enforce. }
           MarkerMsg +
           AccountMsg +
           { CORRECTED 15 Aug 2026, owner, on two counts.

             "with SD started: sd -start" was wrong twice over - SD is started
             by the installer and again at every Windows startup, so there is
             nothing for the user to start, and telling them to do it invites
             them to start a second one.

             "sd -ASDSYS" was wrong because NOBODY LOGS IN TO AN ACCOUNT BUT
             THEIR OWN.  You arrive in your own account and move with LOGTO,
             which is where the grant is checked.  The installer's own account
             step does the same thing. }
           { CORRECTED 16 Aug 2026, owner.  This used to say "From an ELEVATED
             command prompt", which was never the intent and was not what the
             underlying gate required either - that one is rev 0.9.0 and
             predates the port.  Windows does need an elevated token to create
             a user, so SD now obtains one for the session when you enter
             SDSYS, and asks Windows for your consent at that moment.  An
             ordinary command prompt is all that is needed.
             PROJECT_STATUS.md 7 step 4. }
           { THE COMMANDS STAY AND THE PROSE ROUND THEM GOES.  What used to
             follow was four paragraphs explaining LOGTO SDSYS, UAC, remote
             control tools, ssh-only accounts and the ADMINISTRATOR keyword.
             The first page carries the model; a reader who comes back to this
             box comes back for the three lines, not the essay.  The one
             sentence kept is the UAC-over-ssh trap, because its failure mode is
             a frozen screen with no explanation and nothing else warns of it. }
           'TO GIVE SOMEBODY ELSE ACCESS, at the machine itself:' + #13#10#13#10 +
           '    sd' + #13#10 +
           '    LOGTO SDSYS' + #13#10 +
           { THE KEYWORD IS NOT OPTIONAL SINCE 21 AUG 2026 and this line said it
             was, which would have sent the reader straight into message 10082.
             A Phase 2 miss found while writing Phase 3: the verb changed, the
             one place in the product that quotes it did not.  SSH is named
             rather than BOTH because it is what the paragraph below goes on to
             demonstrate. }
           '    CREATE.ACCOUNT USER <name> SSH' + #13#10#13#10 +
           'Windows asks you to confirm at the LOGTO. Do it AT THE MACHINE - ' +
           'over ssh, and under a remote-control tool not installed as a ' +
           'service, Windows cannot show you that prompt and you get a frozen ' +
           'screen instead.' + #13#10#13#10 +
           'The new account signs in over ssh, on this machine as well:' + #13#10#13#10 +
           '    ssh <name>@localhost');

    { Its own box rather than a paragraph in the one above: this one reports
      what happened to a file outside SD's tree, and it can say "nothing was
      changed", which must not be buried under six paragraphs about accounts. }
    if SshLimit <> '' then
      MsgBox(SshLimit, mbInformation, MB_OK);

    if not DataTreeAbsent then
      { 30 Aug 26 - REWRITTEN, BECAUSE IT SAID THE OPPOSITE OF WHAT HAD JUST
        HAPPENED.  PRE_RELEASE_FIXES 77.

        IT FIRED ON THE CONDITION THAT MAKES IT FALSE, which is what made it
        provable rather than arguable: this branch is "not DataTreeAbsent", and
        DataTreeUpgrade is "not DataTreeWasAbsent" - THE SAME PREDICATE - and
        that is what gates the generated upgrade branch's [InstallDelete]
        and [Files] entries.  So "the newly built system files were NOT
        installed over it" was printed at precisely the moment they were.

        ***AND THE LINE ABOVE IS WRAPPED THE WAY IT IS ON PURPOSE.***  ISCC
        splits the file into sections BEFORE any Pascal comment is understood,
        so a bracketed word that starts a line is read as a SECTION TAG even
        inside braces.  This comment first said "... [InstallDelete] and" /
        "[Files].  So ..." and cost a cycle step: "Error on line 3319: Invalid
        section tag.  Compile aborted."  Same class as the "#" hazard the
        SuppressibleMsgBox comment above records - a character that means
        something to a layer that runs before the one you are writing for.
        NEVER LET A LINE IN THIS FILE BEGIN WITH [Anything] UNLESS IT IS
        MEANT AS A SECTION HEADER.  "Upgrading an existing
        database in place is not yet supported" had been false since 25 Aug
        2026, when the owner ruled "preserve the user's own files, replace all
        the shipped ones" and it was built and verified (task table H.3).

        THE ORIGINAL PURPOSE WAS SOUND AND IS KEPT: say out loud what was and
        was not touched, so that nobody has to guess.  What changed is that the
        answer is now the other way round.

        MEASURED BEFORE IT WAS REWORDED, on the owner's own 30 Aug reinstall:
        voc.dic, dict.dic, accounts.dic, $map.dic and three os.users.dic
        records all carried the install's timestamp, in the tree this box had
        just called untouched.

        THE THIRD PARAGRAPH IS NOT PADDING.  sd.conf being onlyifdoesntexist is
        why re-running the installer does NOT turn the API back on, which cost
        the owner a confused half hour on 30 Aug 2026.  Saying it here is the
        cheapest place it can be said.

        EVERY CLAIM BELOW COMES FROM stage.py's OWN LISTS - SDSYS_PRESERVE for
        what is kept, SDSYS_SHIP minus it for what is replaced.  Check it there
        rather than against this comment if either list moves. }
      MsgBox('An existing SD Core database was found at ' + ExpandConstant('{#DataDir}\sdsys') + '.' + #13#10#13#10 +
             'YOUR DATA IS UNTOUCHED: your accounts and their passwords, the account ' +
             'register, anything you catalogued, the print queue, held output, and any ' +
             'programs you wrote in SDSYS''s own BP.' + #13#10#13#10 +
             'SD Core''S OWN SYSTEM FILES WERE REPLACED - the BASIC source and its compiled ' +
             'objects, the VOC templates, the messages and the dictionaries. That is ' +
             'what upgrading in place means, and it is why you are seeing this rather ' +
             'than being asked to uninstall first.' + #13#10#13#10 +
             { 30 Aug 26 - THE LAST SENTENCE WENT STALE BETWEEN BEING WRITTEN AND
               BEING READ, WHICH IS THIS FILE'S OLDEST HABIT.  It said "edit
               sd.conf and restart the SD service", which was the only way when
               77 was fixed a few hours earlier - and PRE_RELEASE 78 shipped
               "remote.api on|local|off" in the SAME install, which does exactly
               that and reads the file back afterwards.  Caught by looking at
               the rendered box rather than at the source.  The tasks-page
               message above carries the same warning from 21 and 25 Aug: "each
               time the text went on asserting the old shape until somebody
               noticed." }
             'YOUR CONFIGURATION WAS NOT CHANGED. sd.conf is left exactly as it is, so ' +
             'settings you edited survive - and re-running this installer will not ' +
             'change them back. To turn the SD Core API on or off afterwards, use the ' +
             '"remote.api" command inside SD Core.',
             mbInformation, MB_OK);

    { AND THE INSTALL ENDS IN SD.  Owner's decision, 21 Aug 2026: the installing
      user's password is collected by leaving them in SD, not by an installer
      password page.  The function's own comment carries why it is here rather
      than in a postinstall [Run] entry, which is where the plan put it.

      LAST OF EVERYTHING, AND AFTER EVERY BOX.  It needs the ACLs set at the
      top of this step and the account AdoptAccount made; and a modal box
      holding focus while SD asks for a password is how a password is typed
      into the wrong window.

      ONLY WHEN AN ACCOUNT WAS JUST MADE.  Code 2 is the reinstall case: that
      account was left alone and keeps whatever password it had.  If it has
      none, LOGIN asks the first time its owner opens it - the rule lives
      there and this is only the install's convenience.

      A SILENT INSTALL NEVER REACHES THIS LINE, because the WizardSilent guard
      above it exits first.  That is deliberate and needs no second test: an
      unattended deployment must not put a console in front of nobody, and the
      account it leaves without a password is the case LOGIN exists for.

      NO BOX IF IT FAILS, ONLY A LOG LINE.  Exec answers whether the process
      STARTED, and the only reason it would not is a missing sd.exe - which the
      user is about to discover for themselves, having just been told to type
      "sd".  There is nothing a box could say that the next thing they do will
      not. }
    { 22 Aug 26 - RECORDED HERE, RUN LATER.  This used to call the password step
      directly, which opened SD while the wizard was still on screen.  Both the
      password step and the check now run from DeinitializeSetup, once the
      window has gone, so all that happens here is remembering what was decided:
      whether the install got this far at all, and whether an account was just
      made and therefore has no password yet. }
    InstallReachedPostInstall := True;
    PasswordStepWanted := (AdoptCode = 0);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  { 22 Aug 26 - THE FINISHED PAGE SAYS WHAT HAPPENS NEXT.  Owner, looking at
    it: "the last pane of the wizard doesn't say anything about the script that
    is going to run after the user clicks Finish".  It said Inno's stock text -
    Setup has finished, click Finish to exit - which is now untrue by omission:
    clicking Finish opens a console window that asks for a password.

    THE EXPLANATION EXISTS ALREADY, in the box at ssPostInstall, and that is
    exactly why this is needed rather than redundant.  That box appears BEFORE
    this page and is dismissed before the reader gets here, so at the moment
    they decide to click Finish there is nothing on screen about it.  A window
    that opens by itself after an installer has apparently finished reads as a
    fault unless the page they clicked said it would.

    FinishedLabel IS THE STOCK LABEL and setting its Caption is the supported
    way to change it; there is no need for a custom page.  Only the ACCOUNT
    half varies, so the text is fixed rather than built. }
  if (CurPageID = wpFinished) and InstallReachedPostInstall and PasswordStepWanted then
  begin
    { THE LABEL HAS TO BE GROWN BEFORE IT IS FILLED, and the first version of
      this did not - the owner's screenshot showed the text cut off mid-sentence
      at "It closes by".  Inno AUTO-SIZES FinishedLabel to the stock text, which
      is three short lines, so anything longer is simply clipped at the old
      height.  Nothing warns: the Caption assignment succeeds and the words are
      just not drawn.

      Taken from the PARENT rather than set to a number, so it is right at any
      DPI and font size.  The stock page leaves the whole area below the label
      empty, so there is nothing under it to overlap. }
    WizardForm.FinishedLabel.Height :=
      WizardForm.FinishedLabel.Parent.ClientHeight - WizardForm.FinishedLabel.Top - ScaleY(8);

    { NO HAND-WRAPPED LINES EITHER.  The label word-wraps, so the leading spaces
      that used to indent the continuation of each numbered item fought with it
      and made the clipping worse.  Only the breaks BETWEEN items are explicit. }
    WizardForm.FinishedLabel.Caption :=
      'Setup has finished installing SD Core on your computer.' + #13#10#13#10 +
      'When you click Finish, one window opens and does two things in turn:' + #13#10#13#10 +
      '1. SD Core asks you to set a password for your SD Core account. It closes by itself once you have set it.' + #13#10#13#10 +
      '2. The same window then checks the installation and reports what it found. It only reads, and it asks before it starts.' + #13#10#13#10 +
      'This is expected. Setting up SD Core is not finished until that window says so.';
  end;

  (* 25 Aug 26 - THE DISCLOSURE PAGE IS RE-TEXTED EVERY TIME IT IS SHOWN, from
     the live radio button rather than from anything remembered.

     WHY IT IS DONE HERE AND NOT ONCE AT CREATION.  InitializeWizard runs before
     the reader has chosen, so the text it seeds the page with is a guess - and
     Back is a supported way through an Inno wizard.  Somebody who reads the
     full disclosure, presses Back, picks stand-alone and comes forward again
     would otherwise be shown the ssh paragraphs for an install that does not
     install ssh.  That is precisely the failure this page has had four times,
     arriving by a new route.

     RichEditViewer.Lines.Text IS WRITABLE - checked by compiling it rather than
     by reading the help, with a control that fails on the same line. *)
  if CurPageID = SummaryPage.ID then
    SummaryPage.RichEditViewer.Lines.Text := DisclosureText;

  { CurPageChanged STILL FIRES IN SILENT MODE, and this box is the only thing
    in the script that could block one.  MEASURED 18 Aug 2026: a cycle run with
    -Silent stopped here with a modal box on screen and copied not one file
    until somebody clicked OK.  The wizard form is created in silent mode and
    simply not shown, so "the page was never displayed" is not the same as
    "the page never changed".

    THE GUARD IS THE ONE ALREADY USED at CurStepChanged rather than a second
    idiom.  SuppressibleMsgBox was the obvious alternative and is the wrong
    one here: it needs /SUPPRESSMSGBOXES, which the comment there records as
    measured NOT to reach these boxes, and it would leave two ways of saying
    the same thing in one file.

    AND IT FIXES THE TEXT AS WELL AS THE HANG.  The box explains why an option
    is "absent from this page" - which is incoherent read in a mode that shows
    no pages, so there was nothing worth showing here anyway.  (It said "two
    options" until 21 Aug 2026; see the note on the message itself.) }
  if WizardSilent then
    Exit;

  { 30 Aug 26 - THE STAND-ALONE GATE IS GONE WITH THE MODE, AND THE CONDITION IS
    NOW JUST "THIS MACHINE ALREADY HAS ssh".  PRE_RELEASE_FIXES 75 and 76.  The
    reader who wants no ssh server does not reach this branch, because on a
    machine that already has one there is no server for them to decline - the
    sshserver box is not even shown. }
  if (CurPageID = wpSelectTasks) and (not SshServerAbsent) then
    { Notify rather than offer, which is what the repository owner asked for:
      the option is not available and the reason is stated.

      REWORDED 16 Aug 2026.  It used to say "the option to install it is
      therefore not offered", which stops making sense once installing is not
      an option anybody is offered.  What the reader needs now is the opposite
      reassurance: SD requires an ssh server, this machine has one, and SD is
      going to keep its hands off it - which is also why BOTH ssh options have
      vanished from the page they are looking at.

      SUPERSEDED 21 Aug 2026 AND KEPT VISIBLE: the last clause is no longer
      true.  Only ONE option vanishes now - limitssh lost its Check and is
      offered on every install.  Left here rather than edited away because the
      history of this box is the point: three rewordings, each one made
      necessary by a change somewhere else in the file, and each time the text
      went on asserting the old shape until somebody noticed. }
    { REWORDED AGAIN 21 Aug 2026, because the limitssh task lost its Check and
      this text would otherwise be false.  It said "the two ssh options are
      absent from this page"; only ONE is now - installing the server, and its
      firewall rule with it.  Limiting ssh IS offered here, on any machine, and
      the sentence has to say so, or the reader ticks a box this box has just
      told them is not there.  Third time this file has been found asserting
      something that had stopped being true; the pattern is worth the note.

      AND AGAIN LATER THE SAME DAY, which makes the point better than the note
      did: limitssh became ticked BY DEFAULT, so "you can still tick it" was
      false in the other direction.  What the reader needs on a machine with
      somebody else's ssh server is to know the box is ALREADY ticked and how
      to refuse it. }
    { REWORDED A FOURTH TIME, 25 Aug 2026, AND THE COMMENT ABOVE PREDICTED IT.
      It says "each time the text went on asserting the old shape until
      somebody noticed" - and this box was still telling the reader to untick
      "Limit ssh to SD users and administrators", a checkbox that no longer
      exists on the page they are looking at.

      WHAT CHANGED UNDER IT.  limitssh stopped being a task; SD's ssh model now
      applies on every install and is disclosed on the "Before you install"
      page instead.  And a machine whose ssh server somebody else CONFIGURED no
      longer reaches this page at all - InitializeSetup refuses it.  So the
      only reader who now sees this box is one with Windows' own OpenSSH
      installed and nobody having touched its configuration, and what they need
      to know is what SD is about to do to it, not which box to untick. }
    MsgBox('OpenSSH Server is already installed on this machine, and SD Core will use ' +
           'it rather than installing another.' + #13#10#13#10 +
           'SD Core has checked it: nothing has changed how it is configured, which is ' +
           'why this install is going ahead. If somebody had changed it, SD Core would ' +
           'have stopped before this point.' + #13#10#13#10 +
           'SD Core WILL NOW CONFIGURE IT, and this is not optional: ssh is limited to ' +
           'SD Core users and administrators, and every ssh session goes straight into ' +
           'SD Core rather than a command prompt. scp and sftp stop working for ' +
           'everyone on this computer as a result. Your existing sshd_config is ' +
           'kept beside it as sshd_config.before-sd. Uninstalling SD Core removes ' +
           'its block and restarts the ssh server, which leaves the file as it ' +
           'was; the copy is there if you would rather put it back yourself.' + #13#10#13#10 +
           'WHO MAY REACH IT IS YOURS TO SET, ON THIS PAGE. The ssh box below ' +
           'starts out matching this computer''s current firewall rule, so if ' +
           'you leave it alone nothing about who can reach port 22 changes. ' +
           'Tick it to let other computers in; untick it to limit ssh to this ' +
           'machine only.' + #13#10#13#10 +
           'Accounts SD Core creates sign in over ssh, so make sure your server ' +
           'accepts them.',
           mbInformation, MB_OK);
end;

{ ---------------------------------------------------------------------------
  Uninstall
  --------------------------------------------------------------------------- }

procedure RemoveFromPath;
var
  Path, Dir, Lower, LowerDir, Rebuilt: String;
  P: Integer;
begin
  (* INNO DOES NOT UNDO AN APPENDED PATH.  The [Registry] entry appends to the
     existing value with the olddata constant, and the uninstaller has no way
     to know which part it contributed - so by default it leaves a dead
     directory on the system PATH for ever.  Measured 14 Aug 2026: after a
     clean uninstall the SD directory was still on PATH.  Strip it by name.

     This comment is not brace-delimited on purpose: a brace comment cannot
     mention a brace-delimited Inno constant, because the first closing brace
     ends the comment and everything after it is parsed as code. *)
  if not RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Path) then
    Exit;

  Dir := ExpandConstant('{app}\usr\bin');
  Lower := ';' + Lowercase(Path) + ';';
  LowerDir := ';' + Lowercase(Dir) + ';';
  P := Pos(LowerDir, Lower);
  if P = 0 then
    Exit;

  { Rebuilt from the original text, so surviving entries keep their case. }
  Rebuilt := Copy(Path, 1, P - 1) + Copy(Path, P + Length(Dir) + 1, MaxInt);
  if (Length(Rebuilt) > 0) and (Rebuilt[1] = ';') then
    Delete(Rebuilt, 1, 1);

  (* AND THE SAME AT THE OTHER END, WHICH WAS MISSING AND LEFT AN EMPTY PATH
     ENTRY BEHIND ON EVERY UNINSTALL.  Reported by the owner on 16 Aug 2026,
     who read the system PATH and found 23 empty entries in 30 - the visible
     symptom being a long run of semicolons that makes it look as though SD
     was never added at all.

     The cause is an asymmetry two lines up: the head copy KEEPS the separator
     that preceded our directory, while the tail copy starts AFTER the one that
     followed it.  With an entry in the middle that is exactly right - "a;" and
     "b" rejoin as "a;b".  With our entry LAST, and Inno always appends so it
     always is, the tail is empty and the kept separator dangles.  The next
     install then appends after it, so the run grows by one every cycle.

     A LOOP, NOT A SINGLE STRIP, AND THAT IS THE USEFUL PART: after our entry
     is removed, every empty slot this bug ever left is trailing, so this
     clears the whole accumulated run on the next uninstall rather than only
     the one just created.  It can only ever delete separators, never a real
     entry, which is what makes it safe to apply to a PATH we do not own. *)
  while (Length(Rebuilt) > 0) and (Rebuilt[Length(Rebuilt)] = ';') do
    Delete(Rebuilt, Length(Rebuilt), 1);

  RegWriteExpandStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Rebuilt);
end;

(* Take SD's AllowGroups block back out of sshd_config.

   BECAUSE IT IS THE ONE THING SD WROTE OUTSIDE ITS OWN TREE.  Everything else
   the uninstaller leaves behind is either the user's data or a group their data
   is ACL'd to; this is a line in somebody else's configuration file, and
   leaving it would keep restricting who may ssh into a machine that no longer
   has SD on it.  The script removes only what is between its own markers and
   is a no-op if the block is not there, so this is safe on a machine where the
   task was never ticked.

   AT usUninstall, NOT usPostUninstall: by the latter the script it runs has
   already been deleted along with the rest of {app}.

   Not brace-delimited, for the reason RemoveFromPath gives above - and this
   comment is how that trap was hit a second time. *)
procedure RemoveAllowGroups;
var
  Ps, Script: String;
  Code: Integer;
begin
  Script := ExpandConstant('{app}\allow-ssh-groups.ps1');
  if not FileExists(Script) then
    Exit;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Remove',
       '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

(* Take SD's own API firewall rule away.

   AND THIS ONE IS REMOVED WHERE THE ssh RULE IS NOT, which looks like the same
   decision going two ways and is not.  The ssh rule was created by the OpenSSH
   capability, the capability stays behind, and putting the rule back would mean
   WIDENING it - an uninstaller must not open a port on its way out.  THE API
   RULE IS SD'S OWN: api-firewall.ps1 created it, it names a port only SD
   listens on, and removing it CLOSES rather than opens.  Leaving it would
   leave a rule for a service that is gone, pointing at a port that will admit
   whatever binds it next.

   AT usUninstall for the same reason as RemoveAllowGroups: by usPostUninstall
   the script has been deleted with the rest of {app}.

   Not brace-delimited - see RemoveFromPath. *)
procedure RemoveApiFirewall;
var
  Ps, Script: String;
  Code: Integer;
begin
  Script := ExpandConstant('{app}\api-firewall.ps1');
  if not FileExists(Script) then
    Exit;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Remove',
       '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

(* Copy the account sweep somewhere that outlives the application directory.

   PRE_RELEASE_FIXES 39.  The sweep is offered AFTER the database question, and
   that question is at usPostUninstall - by which point {app} and everything in
   it is gone.  So the script is taken now, while it still exists.

   A FAILED COPY LEAVES SdAccountsScript EMPTY AND THE PROMPT IS NOT OFFERED.
   Asking a question whose Yes cannot be carried out is worse than not asking.

   Not brace-delimited - see RemoveFromPath. *)
procedure StashAccountSweep;
var
  Src, Dst: String;
begin
  SdAccountsScript := '';
  Src := ExpandConstant('{app}\remove-sdaccounts.ps1');
  if not FileExists(Src) then
    Exit;
  Dst := ExpandConstant('{tmp}\remove-sdaccounts.ps1');
  { 1 Sep 26 - CopyFile, not FileCopy.  Inno renamed the support function and
    warns "Support function FileCopy has been renamed. Use CopyFile instead" on
    every build; identical signature (SourceFile, DestFile, FailIfExists). }
  if CopyFile(Src, Dst, False) then
    SdAccountsScript := Dst;
end;

(* REMOVE SD CORE'S THREE ROUTE GROUPS AT UNINSTALL.  PRE_RELEASE_FIXES 74,
   owner's ruling 2 Sep 2026: "remove the groups at uninstall".

   THREE, NOT FOUR.  sdusers STAYS and its reason is unchanged: deleting it
   would orphan the permissions on the database, which this uninstall
   deliberately leaves behind unless the user asked otherwise.

   sdsshonly IS THE ONE THAT MATTERS, AND REMOVING IT CHANGES BEHAVIOUR RATHER
   THAN JUST TIDYING.  It carries SeDenyInteractiveLogonRight and
   SeDenyRemoteInteractiveLogonRight (deny-logon.ps1:29), so an account KEPT by
   the question above is, until now, still denied the console and Remote Desktop
   by a group belonging to software that has uninstalled itself.  Removing it
   gives those accounts the console back - which is the model the closing page
   already states, "accounts you keep are ordinary Windows accounts once SD Core
   is gone".  A deny that outlives the thing that imposed it was never part of
   that promise.

   UNCONDITIONAL, AND CALLED BEFORE THE TWO QUESTIONS RATHER THAN AFTER THEM.
   The obvious placement is "after the account sweep", and it is wrong: that
   block Exits early three times - no stashed script, no {username}, or the user
   answering No - so a call at the end would be SKIPPED on exactly the common
   path, where the accounts are kept.  These groups go whatever is answered
   about accounts and about the database, so they go where nothing can skip
   them.

   REMOVING THEM FIRST DOES NOT DISTURB THE SWEEP: remove-sdaccounts.ps1 finds
   its candidates through sdusers, which stays, and deleting an account drops
   its memberships anyway.

   net.exe RATHER THAN A SCRIPT, because by usPostUninstall {app} and
   everything in it is gone - the same constraint that makes StashAccountSweep
   copy its script to {tmp} first.  net.exe is in {sys} and is always there.

   A GROUP THAT IS ALREADY ABSENT IS NOT AN ERROR, and the exit code is
   deliberately not tested: net returns non-zero for "does not exist", and a
   stand-alone install never created sdssh or sdapi at all.  An uninstaller that
   reported a failure for work it did not need to do would be worse than one
   that says nothing.  Not brace-delimited - see RemoveFromPath. *)
procedure RemoveSdGroups;
var
  Net: String;
  Code: Integer;
begin
  { 02 Sep 26 - NOT ON A SILENT UNINSTALL.  Owner, 2 Sep 2026: "if we don't
    allow silent installs, we should not allow silent uninstalls."  Refusing
    them outright is not available - cycle.ps1:497 runs the uninstaller with
    /VERYSILENT and the development cycle would stop - but the principle
    applies to THIS step, and it is the step that needed it.

    REMOVING sdsshonly IS A SECURITY-POSTURE CHANGE, NOT TIDYING.  It gives any
    KEPT account the console and Remote Desktop back.  Doing that unattended,
    with nobody shown the closing page that says so, is the shape the owner was
    objecting to.

    SO THE REMOVAL IS TIED TO THE DISCLOSURE: the page that announces it only
    renders on an interactive uninstall, and now so does the removal.  The two
    cannot drift apart, which is what PRE_RELEASE_FIXES 74 was filed about in
    the first place - a disclosure that did not match what was left behind.

    THE COST, STATED: a scripted unattended uninstall still leaves the three
    groups, so 74 is fixed on the interactive path only.  That is the safe
    direction - it leaves MORE behind rather than silently changing who can
    sign in - and it matches sd.iss's existing rule that a silent uninstall
    never deletes the database. }
  if UninstallSilent then
    Exit;

  Net := ExpandConstant('{sys}\net.exe');
  Exec(Net, 'localgroup sdssh /delete',     '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(Net, 'localgroup sdapi /delete',     '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(Net, 'localgroup sdsshonly /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

{ THE TWO DESTRUCTIVE QUESTIONS ASK WITH LABELLED CHOICES, NOT Yes/No.
  Owner's ruling, 2 Sep 2026, on PRE_RELEASE_FIXES 139: "if possible label the
  buttons Keep and Delete, no ambiguity."  He had just answered both prompts on
  guest Test 10 and got both backwards - reporting the database kept and the
  accounts gone, when the data tree was gone and the accounts were untouched.
  Both questions had the same shape, one after the other, and in each of them
  the safe answer was the negative one.

  EVERY FACT BELOW IS MEASURED, not read out of the help, which is a compressed
  .chm and cannot be searched from the build tree.  gplbld/probe-taskdialog.iss
  compiled and ran each one on 2 Sep 2026, and is kept so this is re-checkable
  when Inno changes - three of them are invisible to a compiler:

    MB_YESNO or MB_DEFBUTTON2   COMPILES, then fails at RUN time with "Internal
                                error: TaskDialogMsgBox: Invalid Buttons".  The
                                MB_DEFBUTTON flags are not accepted here, so the
                                default button cannot be set through them.
    bare MB_YESNO               accepted.  Renders as stacked COMMAND LINKS
                                carrying the labels, not as push buttons.
    Labels[0] / Labels[1]       IDYES / IDNO.
    focus                       follows Labels[0].
    Escape, and the X           THERE IS NO X, AND ESCAPE DOES NOTHING.  The
                                dialog cannot be dismissed without choosing,
                                which is why no third outcome is handled below.
    in an UNINSTALLER           WORKS, same mapping as in Setup.  Inno's
                                uninstaller is a separate executable, so this
                                did not follow from the Setup measurement; the
                                probe was made uninstallable and run.

  ***SO THE ORDER IS FORCED RATHER THAN PREFERRED.***  Focus follows Labels[0],
  so the safe answer has to be first - which makes Keep IDYES and Delete IDNO,
  the INVERSE of what both call sites tested before this change.

  THE INVERSION LIVES HERE, ONCE.  Two copies of a reversed test is how the
  next person ships a Keep link that deletes, and this function exists to make
  that impossible rather than merely unlikely.

  NO FALLBACK IS HANDLED, and that is a consequence of MinVersion rather than
  an omission.  The owner's ruling of 2 Sep 2026 admits Windows 10 and 11 and
  nothing earlier, and task dialogs are universal on both, so the plain-MsgBox
  path - where these labels would be lost and the buttons would read Yes/No
  again - cannot arise.  See MinVersion in [Setup]: raise that floor and this
  stays true; lower it and this comment is the thing that stops being so.

  IT RETURNS "DELETE", NOT "YES".  A caller reading "if KeepOrDelete then" is
  reading "if the user chose Delete", which is the question actually asked. }
function KeepOrDelete(const Instruction, Text: String): Boolean;
var
  Labels: TArrayOfString;
begin
  SetArrayLength(Labels, 2);
  Labels[0] := 'Keep';
  Labels[1] := 'Delete';
  Result := TaskDialogMsgBox(Instruction, Text, mbConfirmation, MB_YESNO, Labels, 0) = IDNO;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath, Ps, LogPath, KeepUser: String;
  Code: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    StashAccountSweep;
    RemoveAllowGroups;
    RemoveApiFirewall;
    RemoveFromPath;
    Exit;
  end;

  if CurUninstallStep <> usPostUninstall then
    Exit;

  { PRE_RELEASE_FIXES 74 - see RemoveSdGroups.  Here, not further down, because
    everything below this point can Exit early. }
  RemoveSdGroups;

  { The sdusers group is deliberately NOT removed.  CREATE.ACCOUNT adds every
    SD user to it, and a data tree the user chose to keep is ACL'd to it, so
    deleting the group would orphan the permissions on their own database. }

  { AND THE ssh FIREWALL RULE IS DELIBERATELY NOT PUT BACK, which is worth
    stating because RemoveAllowGroups two procedures up sets the opposite
    precedent - SD reverses what it wrote outside its own tree.

    The asymmetry is deliberate.  Restoring that rule means WIDENING it, and an
    uninstaller must not open a network port on a machine on its way out; a
    server left reachable from itself is the harmless direction to fail in.  SD
    did not create the rule either - the OpenSSH capability did, and the
    capability stays, for the same "it may be in use by something else" reason
    that keeps the server itself installed.

    ssh-firewall.ps1 -Installed -Open is there for somebody who wants it back. }

  DataPath := ExpandConstant('{#DataDir}');
  if not DirExists(DataPath) then
    Exit;

  { A SILENT UNINSTALL MUST NEVER DELETE THE DATABASE.  An unattended removal
    that takes the user's accounts with it is the worst possible default, and
    there is nobody there to answer the question. }
  if UninstallSilent then
    Exit;

  { Names exactly what it destroys and where.  "Do you want to remove your
    settings?" is how people lose data.  The choices are labelled - see
    KeepOrDelete, which carries why, and which returns "the user chose
    Delete" rather than "yes". }
  if KeepOrDelete('Remove the SD Core database?',
            DataPath + #13#10#13#10 +
            'Deleting permanently removes EVERY SD Core account, every password and all ' +
            'data stored in them, including the SDSYS account and your ' +
            'configuration file.' + #13#10#13#10 +
            'Choose Keep to keep them, which is the normal choice - reinstalling ' +
            'SD Core later will find them again.') then
  begin
    if not DelTree(DataPath, True, True, True) then
      MsgBox('Some files under ' + DataPath + ' could not be removed. ' +
             'They may be in use by a running SD Core process.', mbError, MB_OK);
  end;

  { ------------------------------------------------------------------------
    THE SECOND QUESTION - the Windows accounts.  PRE_RELEASE_FIXES 39, owner's
    ruling 29 Aug 2026.  The question above removes the SD-side records; this
    one removes the Windows accounts themselves, and until it existed
    uninstalling left every one of them enabled while REMOVING the sshd_config
    ForceCommand that confined them to SD.

    SEPARATE, AND DEFAULTING TO No, exactly like the database question - the
    ruling asked for "a second separate prompt".

    IT NAMES THE ACCOUNT IT IS KEEPING, IN THE QUESTION.  The ruling requires
    the installing user to be excluded "by construction", and the instrument
    rule applies to an uninstaller too: a wrong answer has to be visible while
    it can still be refused, not discovered at the next sign-in.
    ------------------------------------------------------------------------ }

  if SdAccountsScript = '' then
    Exit;

  KeepUser := ExpandConstant('{username}');
  if KeepUser = '' then
    Exit;

  if not KeepOrDelete('Remove the Windows accounts SD Core created?',
            'These are the accounts CREATE.ACCOUNT made, with their sdu_ and ' +
            'sdg_ groups and their profiles. They are Windows accounts: they ' +
            'keep their passwords and stay able to sign in after SD Core is gone, ' +
            'and the ssh confinement that limited them to SD Core has just been ' +
            'removed with the rest of SD Core''s configuration.' + #13#10#13#10 +
            'The account ' + KeepUser + ' WILL BE KEPT, so you can still sign ' +
            'in to Windows. If that is not the account you expect, choose Keep.' + #13#10#13#10 +
            'Choose Keep to keep them all, which is the safe choice.') then
    Exit;

  { THROUGH cmd SO THE OUTPUT IS KEPT.  The sweep prints what it removed and
    what it kept, and Exec cannot capture that; a window that closes is the
    same as no report at all.  The log is named back to the user below.

    THE SCRIPT REFUSES ON ITS OWN if -Keep names nobody in sdusers, or if the
    sweep would take the last local administrator - so a wrong answer here
    stops there rather than in the middle of the accounts. }
  LogPath := ExpandConstant('{%TEMP|C:\Windows\Temp}\sd-remove-accounts.log');
  Ps := ExpandConstant('{sys}\cmd.exe');
  Exec(Ps, '/c ""' + ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe') +
           '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
           SdAccountsScript + '" -Remove -Keep "' + KeepUser + '" > "' + LogPath + '" 2>&1"',
       '', SW_HIDE, ewWaitUntilTerminated, Code);

  if Code = 0 then
    MsgBox('The Windows accounts SD Core created have been removed, and ' + KeepUser +
           ' was kept.' + #13#10#13#10 +
           'What was removed and what was kept is recorded in:' + #13#10 +
           LogPath + #13#10#13#10 +
           'A profile whose registry hive is still loaded cannot be deleted ' +
           'until the next restart; the log names any that were left.',
           mbInformation, MB_OK)
  else
    MsgBox('The Windows accounts were NOT removed.' + #13#10#13#10 +
           'The sweep refused rather than act on something it could not check - ' +
           'for example if it would have removed the last account able to sign ' +
           'in to Windows.' + #13#10#13#10 +
           'Its reason is in:' + #13#10 + LogPath,
           mbInformation, MB_OK);
end;

function NotOnPath(Dir: String): Boolean;
var
  Path: String;
begin
  Dir := ExpandConstant(Dir);
  if not RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Path) then
  begin
    Result := True;
    Exit;
  end;
  { Semicolons either side so that a directory whose name is a prefix of
    another entry is not mistaken for it. }
  Result := Pos(';' + Lowercase(Dir) + ';', ';' + Lowercase(Path) + ';') = 0;
end;

[Registry]
; The system PATH, so "sd" works from any directory - one of the three things
; the install layout has to deliver (PROJECT_STATUS.md 5.8).  It also means the
; MSYS2 DLLs beside sd.exe are the ones found, which is the answer to Git for
; Windows shipping a rival msys-2.0.dll: Windows searches the executable's own
; directory first, and nothing on PATH can displace it.
;
; 31 Aug 26 - "and not TrueUpgrade", PRE_RELEASE_FIXES 88.  The tasks page is
; not shown on an upgrade, so the box behind this entry carries whatever
; UsePreviousTasks restored rather than anything the reader chose.  NotOnPath
; already makes it a no-op on the ordinary upgrade - the entry is there - but
; that is a coincidence of state, not a decision, and the ruling is that an
; upgrade changes none of these.  append.sd.path on is the way back.
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\usr\bin"; \
    Tasks: addtopath; Check: NotOnPath('{app}\usr\bin') and not TrueUpgrade
