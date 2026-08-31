# suite-only.ps1 - the -Only step filter, shared by VerifyInstall1 and
# VerifyInstall2.  Dot-sourced; it defines one function and runs nothing.
#
# 30 Aug 26 Windows port.  Owner's ruling, 30 Aug 2026, after b73, b74 and b75
# cost about twenty minutes each: "add -Only, and drop the full run to
# milestones".  A full run is ~20 minutes - 4.6 unelevated, 15 elevated - and
# the single step that decides a change is usually 30 to 90 seconds of it.
#
# ONE FILE AND TWO CALLERS, NOT TWO COPIES.  The two runners share nothing
# today, so the obvious thing was to paste the filter into both.  This tree has
# already paid for that shape three times in a week - CRED_SET/MODIFYA, the
# read-back that followed it, and api-firewall/ssh-firewall, where the identical
# bug was fixed in one sibling and not the other.  A filter that drifts between
# the halves would decide DIFFERENT step sets from the same command line.
#
# ***THE FAILURE MODE THIS GUARDS IS "RAN NOTHING AND SAID IT PASSED".***  A
# mistyped step name must not quietly select zero steps and let the runner
# report success, which is the null case CLAUDE.md's instrument rule names
# outright: a test that passes because it did nothing must FAIL, not pass.  So
# every unknown name is refused by name, the kept count is asserted against the
# requested count, and the caller is handed Partial so it can label the run.
#
# IT RETURNS A VERDICT RATHER THAN CALLING exit, and that is what makes it
# testable.  A function that exits cannot be driven by a unit test without
# killing the test process - gplbld/test-suiteonly-units.ps1 drives every branch
# below with no install, no elevation and no run token.  The runners do the
# exiting, on Error.

# NO Set-StrictMode AT FILE SCOPE.  A dot-sourced file's file-scope strict mode
# binds the CALLER, so a strict setting here would silently change how both
# runners behave everywhere else in them.  It goes inside the function instead.

function Select-SuiteSteps {
    <#
    .SYNOPSIS
        Filter a runner's step list by -Only, or pass it through untouched.

    .DESCRIPTION
        Returns an object with three members:

          Steps    the steps to run, IN THE RUNNER'S OWN ORDER
          Partial  $true when -Only narrowed the list, $false when it did not
          Error    '' when the selection is good, otherwise the refusal text

        ORDER IS THE RUNNER'S, NEVER THE CALLER'S.  VerifyInstall1's own ORDER
        comment explains why verify-credacl must be first, and a -Only that
        honoured the order the names were typed in would quietly break that for
        anyone who typed two names the other way round.  Filtering by
        membership preserves it; sorting by the request would not.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Steps,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Only,

        [Parameter(Mandatory = $true)]
        [string] $Runner
    )

    Set-StrictMode -Version Latest

    $result = [pscustomobject]@{
        Steps   = @($Steps)
        Partial = $false
        Error   = ''
    }

    if ($null -eq $Only -or $Only.Trim() -eq '') { return $result }

    # Comma or semicolon, because a shell that eats one usually leaves the
    # other, and getting it wrong costs a whole run to discover.
    $wanted = @($Only -split '[,;]' |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ -ne '' })

    if ($wanted.Count -eq 0) {
        $result.Error = ("{0}: -Only was given as '{1}', which names no step at all." -f $Runner, $Only)
        return $result
    }

    # A name may be typed with or without .ps1.  Compared case-insensitively,
    # DELIBERATELY: these are Windows filenames and NTFS does not distinguish
    # them either, so refusing 'Verify-Tiers' would be this tool inventing a
    # rule the file system does not have.  That is the opposite of the -cne
    # rule this tree uses for hashes, and it is written down so nobody
    # "tightens" it.
    $norm = @($wanted | ForEach-Object {
        if ($_ -match '(?i)\.ps1$') { $_ } else { $_ + '.ps1' }
    })

    # Unique, but on the NORMALISED name, so "verify-tiers,verify-tiers.ps1" is
    # one step rather than a count mismatch.
    $uniq  = @($norm | Sort-Object -Unique)
    $known = @($Steps | ForEach-Object { $_.Name })

    $bad = @($uniq | Where-Object { $known -notcontains $_ })
    if ($bad.Count -gt 0) {
        $result.Error = (
            ("{0}: -Only names {1} step(s) this runner does not have: {2}" -f
                $Runner, $bad.Count, ($bad -join ', ')) + "`n" +
            "  It has these:" + "`n" +
            (($known | ForEach-Object { '    ' + $_ }) -join "`n") + "`n" +
            "  Nothing was run.  A name that matches nothing is refused rather than" + "`n" +
            "  silently selecting no steps, which would report a pass for doing nothing."
        )
        return $result
    }

    $kept = @($Steps | Where-Object { $uniq -contains $_.Name })

    # THE COUNT ASSERTION.  Everything above should make this impossible, which
    # is exactly why it is here: the checks that never fire are the ones that
    # catch a later edit.  A silent mismatch would mean running a different set
    # from the one asked for.
    if ($kept.Count -ne $uniq.Count) {
        $result.Error = ("{0}: -Only asked for {1} step(s) and the filter kept {2}.  Refusing." -f
                         $Runner, $uniq.Count, $kept.Count)
        return $result
    }

    $result.Steps   = $kept
    $result.Partial = ($kept.Count -ne @($Steps).Count)
    return $result
}
