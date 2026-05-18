#pragma once
#include <string>
#include <cerrno>
#include <cstring>
#include <unistd.h>
#include <sys/inotify.h>

// Non-blocking inotify watcher for a single file.
// Watches the parent directory so atomic editor saves (rename-into-place)
// are detected via IN_MOVED_TO in addition to IN_CLOSE_WRITE.
class FileWatcher {
public:
    explicit FileWatcher(const std::string& path) {
        auto sep  = path.rfind('/');
        dir_path_ = (sep == std::string::npos) ? "." : path.substr(0, sep);
        filename_ = (sep == std::string::npos) ? path : path.substr(sep + 1);

        fd_ = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (fd_ < 0) return;

        wd_ = inotify_add_watch(fd_, dir_path_.c_str(),
                                IN_CLOSE_WRITE | IN_MOVED_TO);
        if (wd_ < 0) {
            close(fd_);
            fd_ = -1;
        }
    }

    ~FileWatcher() {
        if (fd_ >= 0) close(fd_);
    }

    FileWatcher(const FileWatcher&)            = delete;
    FileWatcher& operator=(const FileWatcher&) = delete;

    bool valid() const { return fd_ >= 0 && wd_ >= 0; }

    // Returns true if the watched file has changed since the last call.
    // Drains all pending inotify events in the kernel buffer.
    bool poll() {
        if (fd_ < 0) return false;
        alignas(inotify_event) char buf[4096];
        bool changed = false;
        for (;;) {
            ssize_t len = read(fd_, buf, sizeof(buf));
            if (len <= 0) break;  // EAGAIN or error — buffer drained
            for (char* p = buf; p < buf + len; ) {
                auto* ev = reinterpret_cast<inotify_event*>(p);
                if (ev->len > 0 && filename_ == ev->name)
                    changed = true;
                p += static_cast<ssize_t>(sizeof(inotify_event)) + ev->len;
            }
        }
        return changed;
    }

private:
    int         fd_      = -1;
    int         wd_      = -1;
    std::string dir_path_;
    std::string filename_;
};
