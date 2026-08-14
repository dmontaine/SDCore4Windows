# deny-logon.ps1 - confine a local group to ssh by denying it the console and
# Remote Desktop.  Run once by the installer; see PROJECT_STATUS.md 5.6.2.
#
#   powershell -File deny-logon.ps1 <groupname>
#
# Exit 0 success, 1 failure.  Prints what it did either way, because the
# installer step it replaces failed silently and that is the mistake being
# avoided.
#
# WHY LSA AND NOT secedit.  secedit is the only built-in command-line route to
# user rights assignment, and it is a read-modify-write of the ENTIRE
# USER_RIGHTS area: export the policy, edit an .inf, import it back.  That
# rewrites unrelated machine policy and races anything else editing it.
# LsaAddAccountRights adds ONE right to ONE SID and touches nothing else.
# There is no PowerShell cmdlet for this - Get-Command *AccountRight* returns
# nothing - so P/Invoke is the whole of the option space.
#
# TWO RIGHTS, AND NOT A THIRD.  SeDenyInteractiveLogonRight blocks the physical
# console; SeDenyRemoteInteractiveLogonRight blocks Remote Desktop.
# SeDenyNetworkLogonRight IS NOT SET AND MUST NOT BE: Win32-OpenSSH
# authenticates with a network logon - LOGON32_LOGON_NETWORK_CLEARTEXT for
# passwords, S4U for public keys - so denying it would destroy the one route
# this whole design exists to preserve.

param([Parameter(Mandatory=$true)][string]$GroupName)

$ErrorActionPreference = 'Stop'

$rights = @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight')

$signature = @'
using System;
using System.Runtime.InteropServices;

public class SdLsa {
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public int Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    [DllImport("advapi32.dll", SetLastError=true)]
    static extern uint LsaOpenPolicy(IntPtr SystemName,
        ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, int DesiredAccess,
        out IntPtr PolicyHandle);

    [DllImport("advapi32.dll", SetLastError=true)]
    static extern uint LsaAddAccountRights(IntPtr PolicyHandle, byte[] AccountSid,
        LSA_UNICODE_STRING[] UserRights, int CountOfRights);

    [DllImport("advapi32.dll")]
    static extern uint LsaClose(IntPtr PolicyHandle);

    [DllImport("advapi32.dll")]
    static extern int LsaNtStatusToWinError(uint Status);

    // POLICY_CREATE_ACCOUNT | POLICY_LOOKUP_NAMES
    const int POLICY_ACCESS = 0x00000010 | 0x00000800;

    static LSA_UNICODE_STRING MakeString(string s) {
        LSA_UNICODE_STRING u = new LSA_UNICODE_STRING();
        u.Buffer = Marshal.StringToHGlobalUni(s);
        u.Length = (ushort)(s.Length * 2);
        u.MaximumLength = (ushort)((s.Length + 1) * 2);
        return u;
    }

    public static void AddRight(byte[] sid, string right) {
        LSA_OBJECT_ATTRIBUTES attrs = new LSA_OBJECT_ATTRIBUTES();
        attrs.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));

        IntPtr policy;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref attrs, POLICY_ACCESS, out policy);
        if (st != 0)
            throw new Exception("LsaOpenPolicy failed, winerror " + LsaNtStatusToWinError(st));

        LSA_UNICODE_STRING[] rights = new LSA_UNICODE_STRING[1];
        rights[0] = MakeString(right);
        try {
            st = LsaAddAccountRights(policy, sid, rights, 1);
            if (st != 0)
                throw new Exception("LsaAddAccountRights failed, winerror " + LsaNtStatusToWinError(st));
        } finally {
            Marshal.FreeHGlobal(rights[0].Buffer);
            LsaClose(policy);
        }
    }
}
'@

try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "deny-logon: not elevated, cannot set user rights"
        exit 1
    }

    $group = Get-LocalGroup -Name $GroupName -ErrorAction Stop
    $sid = $group.SID
    $bytes = New-Object byte[] $sid.BinaryLength
    $sid.GetBinaryForm($bytes, 0)

    Add-Type -TypeDefinition $signature -Language CSharp | Out-Null

    foreach ($r in $rights) {
        [SdLsa]::AddRight($bytes, $r)
        Write-Output ("deny-logon: granted " + $r + " to " + $GroupName + " (" + $sid.Value + ")")
    }

    Write-Output "deny-logon: done"
    exit 0
}
catch {
    Write-Output ("deny-logon: FAILED - " + $_.Exception.Message)
    exit 1
}
