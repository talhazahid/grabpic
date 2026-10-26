#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
#include <shobjidl.h>
#include <stdio.h>
int wmain(int argc,wchar_t** argv) {
    if(argc!=2) return 1;
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    auto module=LoadLibraryW(argv[1]); if(!module){printf("FAIL LoadLibrary: %lu\n",GetLastError());return 2;}
    using GetClass=HRESULT(WINAPI*)(REFCLSID,REFIID,void**);
    auto get=reinterpret_cast<GetClass>(GetProcAddress(module,"DllGetClassObject"));
    if(!get)return 3;
    CLSID id={0x4d57b652,0xa8d7,0x4dda,{0xa7,0xfa,0x49,0xa6,0x17,0xb7,0x62,0x90}};
    IClassFactory* factory=nullptr; if(FAILED(get(id,IID_IClassFactory,reinterpret_cast<void**>(&factory))))return 4;
    IExplorerCommand* root=nullptr; if(FAILED(factory->CreateInstance(nullptr,IID_IExplorerCommand,reinterpret_cast<void**>(&root))))return 5;
    factory->Release(); PWSTR title=nullptr; if(FAILED(root->GetTitle(nullptr,&title))||wcscmp(title,L"Grab Pic"))return 6; CoTaskMemFree(title);
    EXPCMDFLAGS flags; if(FAILED(root->GetFlags(&flags))||flags!=ECF_HASSUBCOMMANDS)return 7;
    PWSTR icon=nullptr; if(FAILED(root->GetIcon(nullptr,&icon))||GetFileAttributesW(icon)==INVALID_FILE_ATTRIBUTES)return 8; CoTaskMemFree(icon);
    IEnumExplorerCommand* items=nullptr; if(FAILED(root->EnumSubCommands(&items)))return 9;
    const wchar_t* names[]={L"Grab Full Screen",L"Grab Area",L"Open Captures",L"Settings"};
    for(int i=0;i<4;i++) { IExplorerCommand* child=nullptr; ULONG count=0; if(items->Next(1,&child,&count)!=S_OK||count!=1)return 10; if(FAILED(child->GetTitle(nullptr,&title))||wcscmp(title,names[i]))return 11; CoTaskMemFree(title); child->Release(); }
    IExplorerCommand* child=nullptr; if(items->Next(1,&child,nullptr)!=S_FALSE)return 12;
    items->Reset(); IEnumExplorerCommand* clone=nullptr; if(FAILED(items->Clone(&clone)))return 13; clone->Release(); items->Release(); root->Release();
    using CanUnload=HRESULT(WINAPI*)(); auto unload=reinterpret_cast<CanUnload>(GetProcAddress(module,"DllCanUnloadNow")); if(!unload||unload()!=S_OK)return 14;
    FreeLibrary(module); CoUninitialize(); puts("PASS Native menu: COM activation, title, flags, icon, four actions, enumeration, clone, and release"); return 0;
}
