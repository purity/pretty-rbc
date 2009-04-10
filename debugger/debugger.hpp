#ifndef RBX_DEBUGGER_HPP
#define RBX_DEBUGGER_HPP

#include "vm.hpp"
#include "builtin/object.hpp"
#include "call_frame.hpp"
#include "builtin/compiledmethod.hpp"
#include "builtin/tuple.hpp"
#include "builtin/iseq.hpp"

namespace rubinius {

  class Debugger {
  private:
    pthread_mutex_t mutex;
    uint32_t num_records;
    uint32_t options;
    const char* read_file;
    const char* write_file;
    uint64_t instruction_count;
    uint64_t bp_instruction_count;

    enum breakpoint_types {
      NEXT_BREAKPOINT = 1,
      STEP_BREAKPOINT = 2,
      CUSTOM_BREAKPOINT = 4
    };

    enum options {
      IGNORE_STEP_BREAKPOINT = 1,
      IGNORE_CUSTOM_BREAKPOINT = 2,
      NO_DEBUG_DIR = 4
    };

  private:
    void set_files();
    void write_record(const char* out);
    void write_header(STATE, CallFrame* call_frame);
    bool execute_command(STATE, CallFrame* call_frame, const char* cmd);
    void poll_file(STATE, CallFrame* call_frame);
    const char* extract_pid(const char* cmd, uintptr_t* pid);
    const char* extract_number(const char* cmd, uint32_t* num);
    void rtrim(char* str);
    bool numeric_string(char* str);
    opcode get_opcode(STATE, Tuple* tup, uint32_t idx);
    const char* pointer_role(Object* obj);
    void allocate_breakpoints(CompiledMethod* cm);
    CompiledMethod* get_method(STATE, const char* cmd);
    CompiledMethod* get_method(STATE, Class* cls, const char* method_name);
    const char* class_path(STATE, const char* cmd, Class** kls);

  public:
    Debugger();
    void run(STATE, CallFrame* call_frame);
  };
}

#endif

