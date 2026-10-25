// sdclient.cs - SD client API (sdclilib) bindings for C# and .NET, with P/Invoke.
//
// 15 Oct 2026.  The library's own signatures are in gplsrc/sdclilib.h and win over this file; gplbld/test-clientheaders-units.py
// holds every declaration below against that header (the names, the number of parameters and their types).
//
// WINDOWS AND LINUX.  The library is named "sdclilib": .NET loads sdclilib.dll on Windows (the C client library of the Windows kit,
// not the Visual Basic DLL sdclient.dll, whose calls are stdcall) and sdclilib.so or libsdclilib.so on Linux (the installed copy is
// /usr/local/sdsys/bin/sdclilib.so).  Both are cdecl and have the same functions, and a client of either kind talks to a server of
// either kind: a Windows program can use an SD server on Linux and a Linux program one on Windows.  Put the library where .NET
// looks (the program's own directory, or PATH / LD_LIBRARY_PATH), or point .NET at it with NativeLibrary.SetDllImportResolver.
// A 64-bit program needs the 64-bit library and a 32-bit program the 32-bit one.
//
// STRINGS ARE BYTES.  SD strings carry the marks 0xFB to 0xFF (item, field, value, subvalue and text marks) and a UTF-8
// conversion by .NET would damage them, so every string parameter is a byte[] and every string result an IntPtr, and the two
// helpers below turn one into the other with ONE CHARACTER FOR EACH BYTE (ISO 8859-1):
//     Z("text")      a string as the NUL-terminated byte[] a parameter wants (characters above 255 are not allowed)
//     Str(ptr)       a result as a string, and the library's memory given back with SDFree; null for a null pointer
//     StrN(ptr, n)   the same for n bytes that may hold zeros (SDReadBlk); give it the Actual the call returned
// Every function that returns a string returns memory the library allocated: Str and StrN free it, and a result you read any
// other way you must pass to SDFree yourself.  The marks as constants: SDClient.FM (0xFE), VM (0xFD), SVM (0xFC).
//
// CALLS.  Variadic C functions cannot be declared in C#, so SDCall and SDCallx are declared for every number of arguments from 0 to
// 20: SDCall0 ... SDCall20 and SDCallx0 ... SDCallx20 (the same entry point).  SDCall writes the subroutine's results back INTO
// THE BUFFERS YOU PASSED, with no check of their size: use SDCallx and read the arguments with SDGetArg unless every buffer is as
// big as any result can be.  An int * parameter is an out int: SDRead(fno, Z(id), out int err).
//
//     using static SDClient;   // or SDClient.SDConnect(...)
//     if (SDConnect(Z("server"), 4247, Z("user"), Z("password"), Z("account")) != 0)
//     {
//         int fno = SDOpen(Z("CUSTOMERS"));
//         string rec = Str(SDRead(fno, Z("1001"), out int err));
//         SDDisconnect();
//     }

using System;
using System.Runtime.InteropServices;

public static class SDClient
{
    const string Lib = "sdclilib";
    const CallingConvention CC = CallingConvention.Cdecl;

    // Server status constants (sorted)
    public const int SV_ELSE = 2;
    public const int SV_ERROR = 3;
    public const int SV_LOCKED = 4;
    public const int SV_OK = 0;
    public const int SV_ON_ERROR = 1;
    public const int SV_PROMPT = 5;
    public const int SV_ECONTXT = 7;
    public const int SV_EMSG_PAIR = 6;

    // The marks, as characters
    public const char FM = (char)0xFE;
    public const char VM = (char)0xFD;
    public const char SVM = (char)0xFC;

    public static byte[] Z(string s)
    {
        if (s == null) return null;
        byte[] b = new byte[s.Length + 1];
        for (int i = 0; i < s.Length; i++) b[i] = (byte)s[i];
        return b;
    }

    public static string StrN(IntPtr p, int n)
    {
        if (p == IntPtr.Zero) return null;
        if (n < 0) n = 0;
        byte[] b = new byte[n];
        if (n > 0) Marshal.Copy(p, b, 0, n);
        SDFree(p);
        char[] c = new char[n];
        for (int i = 0; i < n; i++) c[i] = (char)b[i];
        return new string(c);
    }

    public static string Str(IntPtr p)
    {
        if (p == IntPtr.Zero) return null;
        int n = 0;
        while (Marshal.ReadByte(p, n) != 0) n++;
        return StrN(p, n);
    }

    // The functions (sorted)
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDChange(byte[] src, byte[] old_string, byte[] new_string, int occurrences, int start);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDChecksum(byte[] data);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDClearSelect(int listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDClose(int fno);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDConnect(byte[] host, int port, byte[] username, byte[] password, byte[] account);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDConnectLocal(byte[] account);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDConnected();
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDDcount(byte[] src, byte[] delim);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDDebug(short mode);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDDel(byte[] src, int fno, int vno, int svno);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDDelete(int fno, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDDeleteu(int fno, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDDisconnect();
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDDisconnectAll();
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDEndCommand();
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDError();
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDEvalConv(int fno, byte[] name, byte[] data, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDEvaluate(int fno, byte[] name, byte[] data, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDExecute(byte[] command, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDExtract(byte[] src, int fno, int vno, int svno);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDField(byte[] src, byte[] delim, int first, int occurrences);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDFree(IntPtr p);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDGetArg(int arg_number);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDGetSession();
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDGetVar(byte[] name);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDIConv(byte[] data, byte[] code);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDIConvs(byte[] data, byte[] code);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDIndices(int fno, byte[] index_name);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDIns(byte[] src, int fno, int vno, int svno, byte[] new_string);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDLocate(byte[] item, byte[] src, int fno, int vno, int svno, out int pos, byte[] order);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDLogto(byte[] account_name);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDMarkMapping(short fno, short state);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDMatch(byte[] str, byte[] pattern);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDMatchfield(byte[] str, byte[] pattern, int component);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDOConv(byte[] data, byte[] code);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDOConvs(byte[] data, byte[] code);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDOpen(byte[] filename);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDOpenSeq(byte[] filename, byte[] id, int modes);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDRead(int fno, byte[] id, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadBlk(int fno, int bytes, out int actual);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadl(int fno, byte[] id, int wait, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadList(int listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadNext(short listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadSeq(int fno, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReadu(int fno, byte[] id, int wait, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDRecordlock(int fno, byte[] id, int update_lock, int wait);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDRecordlocked(int fno, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDRelease(int fno, byte[] id);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDReplace(byte[] src, int fno, int vno, int svno, byte[] new_string);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDRespond(byte[] response, out int err);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDRevision();
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDRTrans(byte[] file_name, byte[] id, byte[] field_name, byte[] action);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDSeek(int fno, int offset, int relto);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDSelect(int fno, int listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDSelectIndex(short fno, byte[] index_name, byte[] index_value, short listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDSelectLeft(short fno, byte[] index_name, short listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDSelectRight(short fno, byte[] index_name, short listno);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDSetLeft(short fno, byte[] index_name);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDSetRight(short fno, byte[] index_name);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDSetSession(int session);
    [DllImport(Lib, CallingConvention = CC)] public static extern int SDStatus();
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDSystem(int key);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDTrans(byte[] file_name, byte[] id, byte[] field_name, byte[] action);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDTxn(int mode);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDWeofSeq(int fno);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDWrite(int fno, byte[] id, byte[] data);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDWriteBlk(int fno, byte[] rec, int bytes);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDWriteSeq(int fno, byte[] rec);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDWriteSeqKey(int fno, byte[] rec);
    [DllImport(Lib, CallingConvention = CC)] public static extern void SDWriteu(int fno, byte[] id, byte[] data);
    [DllImport(Lib, CallingConvention = CC)] public static extern IntPtr SDWriteuSeqKey(int fno, byte[] rec);

    // SDCall and SDCallx for 0 to 20 arguments (the C functions are variadic; every argument is a char *)
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall0(byte[] subrname, short argc);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall1(byte[] subrname, short argc, byte[] a1);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall2(byte[] subrname, short argc, byte[] a1, byte[] a2);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall3(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall4(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall5(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall6(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall7(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall8(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall9(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall10(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall11(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall12(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall13(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall14(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall15(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall16(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall17(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall18(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall19(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18, byte[] a19);
    [DllImport(Lib, EntryPoint = "SDCall", CallingConvention = CC)] public static extern void SDCall20(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18, byte[] a19, byte[] a20);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx0(byte[] subrname, short argc);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx1(byte[] subrname, short argc, byte[] a1);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx2(byte[] subrname, short argc, byte[] a1, byte[] a2);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx3(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx4(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx5(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx6(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx7(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx8(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx9(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx10(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx11(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx12(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx13(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx14(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx15(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx16(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx17(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx18(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx19(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18, byte[] a19);
    [DllImport(Lib, EntryPoint = "SDCallx", CallingConvention = CC)] public static extern void SDCallx20(byte[] subrname, short argc, byte[] a1, byte[] a2, byte[] a3, byte[] a4, byte[] a5, byte[] a6, byte[] a7, byte[] a8, byte[] a9, byte[] a10, byte[] a11, byte[] a12, byte[] a13, byte[] a14, byte[] a15, byte[] a16, byte[] a17, byte[] a18, byte[] a19, byte[] a20);
}
