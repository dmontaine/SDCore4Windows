/* probe-pylimited.c - PROJECT_STATUS.md section 8, constraint 5.
 *
 * THE QUESTION.  sdpy.exe (section 5.27, the ruled helper) has to link against
 * SOMETHING.  Two routes:
 *
 *   EXACT    python314.lib / python314.dll - the whole C API, but the binary
 *            only ever works with that one Python version.
 *   LIMITED  python3.lib / python3.dll with Py_LIMITED_API - one binary works
 *            with every Python at or above the floor it was compiled for.
 *
 * Section 8 records this as "Undecided", and it is the last thing that could
 * change the shape of the helper.  This probe MEASURES the difference instead
 * of reasoning about it.  Build it both ways and read what each one says.
 *
 * ***IT IS BUILT WITH THE UCRT64 COMPILER, NOT MSYS2's.***  Section 5.3: the
 * server is MSYS2 and python.org's DLL is native, and the two runtimes never
 * meet in one process.  The helper exists precisely so that boundary is a pipe
 * rather than a linker flag, so the probe must be built the way the helper
 * would be - like the client DLLs.
 *
 * WHAT IT PRINTS, and every line of it is evidence rather than a verdict:
 *   - which build this is, and whether Py_LIMITED_API really ended up defined
 *   - which python DLL the PROCESS actually bound, read back from the loader
 *     rather than assumed from the link line
 *   - sys.version, proving the interpreter really ran
 *
 * ***THE DLL READBACK IS THE POINT.***  Linking python3.lib is supposed to bind
 * python3.dll, which forwards to whichever pythonXY.dll is installed.  Nobody
 * here has seen that happen, and a probe that only printed "it worked" would
 * not distinguish it from having quietly bound python314.dll directly.
 *
 * Exit 0 the interpreter started and answered, 2 it did not.
 */

#ifdef USE_LIMITED
/* 0x030D0000 is 3.13 - DELIBERATELY BELOW the 3.14 installed here.  If the
 * limited route works, a helper built against this floor runs on 3.13 and
 * every later 3.x, which is the whole reason the route is interesting.  The
 * floor is a BUILD-time choice, so it does not have to match what is
 * installed. */
#define Py_LIMITED_API 0x030D0000
#endif

#include <Python.h>
#include <windows.h>
#include <stdio.h>

static void report_loaded_dll(void) {
    /* Read from the loader, not from the link line. */
    static const char* names[] = { "python3.dll", "python314.dll",
                                   "python313.dll", "python312.dll", NULL };
    int found = 0;
    int i;
    for (i = 0; names[i] != NULL; i++) {
        HMODULE h = GetModuleHandleA(names[i]);
        if (h != NULL) {
            char path[MAX_PATH];
            path[0] = '\0';
            if (GetModuleFileNameA(h, path, (DWORD)sizeof(path)) == 0)
                (void)snprintf(path, sizeof(path), "(path unavailable)");
            printf("  bound: %-14s %s\n", names[i], path);
            found++;
        }
    }
    /* REFUSE THE NULL CASE.  No python DLL in the process means the numbers
     * below came from somewhere this probe does not understand. */
    if (found == 0)
        printf("  bound: NONE FOUND - that is not a result, it is a broken probe\n");
}

int main(void) {
#ifdef USE_LIMITED
    printf("probe-pylimited: build = LIMITED (python3.lib)\n");
#else
    printf("probe-pylimited: build = EXACT (python314.lib)\n");
#endif

#ifdef Py_LIMITED_API
    printf("  Py_LIMITED_API: defined as 0x%08lX\n", (unsigned long)Py_LIMITED_API);
#else
    printf("  Py_LIMITED_API: NOT defined - full C API\n");
#endif

    Py_Initialize();
    if (!Py_IsInitialized()) {
        printf("  FAIL: Py_Initialize() did not initialise an interpreter\n");
        return 2;
    }

    report_loaded_dll();

    {
        /* sys.version through calls that exist in the LIMITED api too, so the
         * two builds differ only in how they were compiled and linked. */
        PyObject* sys = PyImport_ImportModule("sys");
        PyObject* ver = NULL;
        PyObject* enc = NULL;
        if (sys == NULL) { printf("  FAIL: import sys\n"); Py_Finalize(); return 2; }
        ver = PyObject_GetAttrString(sys, "version");
        if (ver == NULL) { printf("  FAIL: sys.version\n"); Py_DecRef(sys); Py_Finalize(); return 2; }
        enc = PyUnicode_AsUTF8String(ver);
        if (enc == NULL) { printf("  FAIL: encode sys.version\n"); Py_DecRef(ver); Py_DecRef(sys); Py_Finalize(); return 2; }
        printf("  sys.version: %s\n", PyBytes_AsString(enc));
        Py_DecRef(enc); Py_DecRef(ver); Py_DecRef(sys);
    }

    Py_Finalize();
    printf("  interpreter started, answered, and finalised cleanly\n");
    return 0;
}
