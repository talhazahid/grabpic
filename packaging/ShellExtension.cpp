#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <new>

static HMODULE moduleHandle;
static LONG objects = 0;
static const CLSID RootId = {0x4d57b652,0xa8d7,0x4dda,{0xa7,0xfa,0x49,0xa6,0x17,0xb7,0x62,0x90}};
static HRESULT Text(const wchar_t* source, PWSTR* output) {
    if (!output) return E_POINTER;
    size_t bytes = (wcslen(source)+1)*sizeof(wchar_t);
    *output = static_cast<PWSTR>(CoTaskMemAlloc(bytes));
    if (!*output) return E_OUTOFMEMORY;
    CopyMemory(*output, source, bytes); return S_OK;
}
static void AppPath(wchar_t* path, const wchar_t* file) {
    GetModuleFileNameW(moduleHandle, path, 32768);
    wchar_t* slash = wcsrchr(path, L'\\'); if (slash) slash[1]=0;
    wcscat_s(path,32768,file);
}
class Commands;
class Command final : public IExplorerCommand {
    LONG refs = 1; int action;
public:
    explicit Command(int id=0):action(id) { InterlockedIncrement(&objects); }
    ~Command() { InterlockedDecrement(&objects); }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override { if(!out) return E_POINTER; *out=nullptr; if(IsEqualIID(id,IID_IUnknown)||IsEqualIID(id,IID_IExplorerCommand)) { *out=static_cast<IExplorerCommand*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { LONG left=InterlockedDecrement(&refs); if(!left) delete this; return left; }
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*,PWSTR* out) override { const wchar_t* titles[]={L"Grab Pic",L"Grab Full Screen",L"Grab Area",L"Open Captures",L"Settings"}; return Text(titles[action],out); }
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*,PWSTR* out) override { wchar_t path[32768]; AppPath(path,L"Assets\\GrabPic.ico"); return Text(path,out); }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*,PWSTR* out) override { return Text(L"Capture. Copy. Carry on.",out); }
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* out) override { if(!out) return E_POINTER; *out=RootId; out->Data4[7]+=static_cast<BYTE>(action); return S_OK; }
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray*,BOOL,EXPCMDSTATE* out) override { if(!out) return E_POINTER; *out=ECS_ENABLED; return S_OK; }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray*,IBindCtx*) override { if(!action) return S_OK; const wchar_t* args[]={L"show",L"full",L"area",L"folder",L"settings"}; wchar_t path[32768]; AppPath(path,L"GrabPic.exe"); auto result=ShellExecuteW(nullptr,L"open",path,args[action],nullptr,SW_SHOWNORMAL); return reinterpret_cast<INT_PTR>(result)>32 ? S_OK : E_FAIL; }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* out) override { if(!out) return E_POINTER; *out=action==0 ? ECF_HASSUBCOMMANDS : ECF_DEFAULT; return S_OK; }
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** out) override;
};
class Commands final : public IEnumExplorerCommand {
    LONG refs=1; ULONG index=0;
public:
    Commands() { InterlockedIncrement(&objects); }
    ~Commands() { InterlockedDecrement(&objects); }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override { if(!out) return E_POINTER; *out=nullptr; if(IsEqualIID(id,IID_IUnknown)||IsEqualIID(id,IID_IEnumExplorerCommand)) { *out=static_cast<IEnumExplorerCommand*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { LONG left=InterlockedDecrement(&refs); if(!left) delete this; return left; }
    HRESULT STDMETHODCALLTYPE Next(ULONG count,IExplorerCommand** commands,ULONG* fetched) override { if(!commands || (count!=1&&!fetched)) return E_POINTER; ULONG done=0; while(done<count&&index<4) { commands[done]=new(std::nothrow) Command(static_cast<int>(index+1)); if(!commands[done]) { if(fetched) *fetched=done; return E_OUTOFMEMORY; } ++index; ++done; } if(fetched) *fetched=done; return done==count ? S_OK : S_FALSE; }
    HRESULT STDMETHODCALLTYPE Skip(ULONG count) override { ULONG remaining=4-index; index+=count<remaining?count:remaining; return count<=remaining?S_OK:S_FALSE; }
    HRESULT STDMETHODCALLTYPE Reset() override { index=0; return S_OK; }
    HRESULT STDMETHODCALLTYPE Clone(IEnumExplorerCommand** out) override { if(!out) return E_POINTER; auto clone=new(std::nothrow) Commands(); if(!clone) return E_OUTOFMEMORY; clone->index=index; *out=clone; return S_OK; }
};
HRESULT Command::EnumSubCommands(IEnumExplorerCommand** out) { if(!out) return E_POINTER; *out=nullptr; if(action) return E_NOTIMPL; *out=new(std::nothrow) Commands(); return *out?S_OK:E_OUTOFMEMORY; }
class Factory final : public IClassFactory {
    LONG refs=1;
public:
    Factory() { InterlockedIncrement(&objects); } ~Factory() { InterlockedDecrement(&objects); }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override { if(!out) return E_POINTER; *out=nullptr; if(IsEqualIID(id,IID_IUnknown)||IsEqualIID(id,IID_IClassFactory)) { *out=static_cast<IClassFactory*>(this); AddRef(); return S_OK; } return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { LONG left=InterlockedDecrement(&refs); if(!left) delete this; return left; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID id,void** out) override { if(outer) return CLASS_E_NOAGGREGATION; auto command=new(std::nothrow) Command(); if(!command) return E_OUTOFMEMORY; HRESULT result=command->QueryInterface(id,out); command->Release(); return result; }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if(lock) InterlockedIncrement(&objects); else InterlockedDecrement(&objects); return S_OK; }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid,REFIID iid,void** out) { if(!IsEqualCLSID(clsid,RootId)) return CLASS_E_CLASSNOTAVAILABLE; auto factory=new(std::nothrow) Factory(); if(!factory) return E_OUTOFMEMORY; HRESULT result=factory->QueryInterface(iid,out); factory->Release(); return result; }
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects==0?S_OK:S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) { if(reason==DLL_PROCESS_ATTACH) { moduleHandle=instance; DisableThreadLibraryCalls(instance); } return TRUE; }
