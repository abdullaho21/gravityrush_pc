#pragma once
// GOW3_TIME_TRACE=1 (src/runtime_kernel.c): per-thread counts of the guest's clock and frame calls,
// printed with every Frame stats line. The numbers match the TT_* enum in src/runtime.h.
extern "C" void runtime_time_trace(int which);
extern "C" void runtime_time_trace_report(void);
namespace Gow3TimeTrace {
enum : int { FlipStatus = 12, VblankStatus = 13, WaitEqueue = 14, Flip = 16, GnmFlip = 17 };
}
