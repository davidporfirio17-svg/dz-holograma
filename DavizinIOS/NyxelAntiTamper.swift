import Foundation
import Darwin
import MachO

enum NyxelAntiTamper {
    enum Verdict {
        case pass
        case suspect(String)
        var isSuspect: Bool { if case .suspect = self { return true } else { return false } }
    }

    static func inspect() -> Verdict {
        if isBeingDebugged() { return .suspect("DBG-001") }
        if hasFridaSignature() { return .suspect("DBG-002") }
        if hasSuspiciousDyldImages() { return .suspect("DBG-003") }
        if hasDyldInsertLibraries() { return .suspect("DBG-004") }
        if hasFridaNamedPipe() { return .suspect("DBG-005") }
        if hasExceptionPortHijack() { return .suspect("DBG-006") }
        if hasSuspiciousFiles() { return .suspect("DBG-007") }
        return .pass
    }

    static func denyPtraceAttach() {
        typealias PtraceFn = @convention(c) (Int32, pid_t, UnsafeMutableRawPointer?, Int32) -> Int32
        let PT_DENY_ATTACH: Int32 = 31
        let handle = dlopen(nil, RTLD_NOW)
        if let sym = dlsym(handle, "ptrace") {
            let ptraceFn = unsafeBitCast(sym, to: PtraceFn.self)
            _ = ptraceFn(PT_DENY_ATTACH, 0, nil, 0)
        }
    }

    private static func isBeingDebugged() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.size
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if junk != 0 { return false }
        let P_TRACED: Int32 = 0x00000800
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    private static func hasFridaSignature() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(27042).bigEndian
        addr.sin_addr.s_addr = UInt32(0x7F000001).bigEndian
        let r = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                connect(fd, sap, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    private static func hasSuspiciousDyldImages() -> Bool {
        let needles = [
            "FridaGadget", "frida", "cynject", "libcycript",
            "SubstrateLoader", "MobileSubstrate", "SubstrateInserter",
            "SSLKillSwitch", "ssl-kill-switch", "flexdecrypt",
            "shadow.dylib", "Liberty", "A-Bypass", "FlyJB",
            "Choicy", "TweakInject", "ellekit", "substitute"
        ]
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let raw = _dyld_get_image_name(i) else { continue }
            let name = String(cString: raw).lowercased()
            if needles.contains(where: { name.contains($0.lowercased()) }) {
                return true
            }
        }
        return false
    }

    private static func hasDyldInsertLibraries() -> Bool {
        getenv("DYLD_INSERT_LIBRARIES") != nil
    }

    private static func hasFridaNamedPipe() -> Bool {
        let pipes = ["/tmp/frida-", "/tmp/re.frida", "/tmp/frida.pipe"]
        for p in pipes {
            if access(p, F_OK) == 0 { return true }
            var buf = stat()
            if lstat(p, &buf) == 0 { return true }
        }
        return false
    }

    private static func hasExceptionPortHijack() -> Bool {
        var masks = exception_mask_t(EXC_MASK_ALL)
        var ports = mach_port_t(MACH_PORT_NULL)
        var behaviors = exception_behavior_t(0)
        var flavors = thread_state_flavor_t(0)
        var count = mach_msg_type_number_t(1)
        let kr = withUnsafeMutablePointer(to: &masks) { mp in
            withUnsafeMutablePointer(to: &ports) { pp in
                withUnsafeMutablePointer(to: &behaviors) { bp in
                    withUnsafeMutablePointer(to: &flavors) { fp in
                        task_get_exception_ports(
                            mach_task_self_,
                            exception_mask_t(EXC_MASK_ALL),
                            mp, &count, pp, bp, fp
                        )
                    }
                }
            }
        }
        if kr != KERN_SUCCESS { return false }
        return count > 0 && ports != mach_port_t(MACH_PORT_NULL)
    }

    private static func hasSuspiciousFiles() -> Bool {
        let paths = [
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/substrate",
            "/usr/lib/TweakInject",
            "/var/lib/dpkg/info",
            "/usr/sbin/frida-server",
            "/usr/bin/cycript"
        ]
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { return true }
        }
        return false
    }
}
