#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int) {
    wchar_t exe[32768], command[32768]; GetModuleFileNameW(nullptr,exe,32768);
    wchar_t* slash=wcsrchr(exe,L'\\'); if(!slash) return 1; slash[1]=0;
    wcscat_s(exe,32768,L"GrabPic.exe"); wcscpy_s(command,32768,L"\""); wcscat_s(command,32768,exe); wcscat_s(command,32768,L"\" background");
    STARTUPINFOW startup={sizeof(startup)}; PROCESS_INFORMATION process={};
    if(!CreateProcessW(exe,command,nullptr,nullptr,FALSE,0,nullptr,nullptr,&startup,&process)) return 1;
    CloseHandle(process.hThread); CloseHandle(process.hProcess); return 0;
}
