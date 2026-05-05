#pragma once
#include <array>
#include <atomic>
#include <cstdint>

static constexpr int MAX_ORBITAL_POINTS = 16384;

// Cache-line aligned to avoid false sharing between solver and render threads.
struct alignas(64) SolverBuffer {
    std::array<float, MAX_ORBITAL_POINTS * 3> positions{};  // x,y,z interleaved (km)
    std::array<float, MAX_ORBITAL_POINTS>     timestamps{}; // seconds since epoch
    int32_t  point_count{0};
    uint64_t frame_id{0};
};

// Lock-free double buffer — solver writes back(), render reads front().
// Swap is a single atomic XOR: zero contention, zero blocking.
class DoubleBuffer {
public:
    SolverBuffer& back()  { return buffers_[1 - front_.load(std::memory_order_acquire)]; }
    SolverBuffer& front() { return buffers_[front_.load(std::memory_order_acquire)]; }

    // Called by solver thread after writing a complete frame.
    void swap() { front_.fetch_xor(1, std::memory_order_acq_rel); }

    // Returns true if a new frame has been produced since last call.
    bool has_new_frame(uint64_t last_seen_id) const {
        return buffers_[front_.load(std::memory_order_acquire)].frame_id != last_seen_id;
    }

private:
    SolverBuffer        buffers_[2];
    std::atomic<int>    front_{0};
};
