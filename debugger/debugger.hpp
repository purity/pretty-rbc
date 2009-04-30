#ifndef RBX_DEBUGGER_HPP
#define RBX_DEBUGGER_HPP

#include "vm.hpp"
#include "builtin/object.hpp"
#include "call_frame.hpp"
#include "builtin/compiledmethod.hpp"
#include "builtin/tuple.hpp"
#include "builtin/iseq.hpp"

namespace rubinius {
  typedef std::map<Object*, bool> SelfPointers;

  class Debugger {
  public:
    pthread_mutex_t mutex;

  private:
    uint32_t num_records;
    uint32_t options;
    const char* read_file;
    const char* write_file;
    uint64_t instruction_count;
    uint64_t bp_instruction_count;
    uintptr_t thread_id;

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
    static uintptr_t hex_char_to_num(char hex, uintptr_t* pow16);
    static uintptr_t dec_char_to_num(char dec, uintptr_t* pow10);

  private:
    void set_files();
    void write_record(const char* out);
    void write_header(STATE, CallFrame* call_frame);
    bool execute_command(STATE, CallFrame* call_frame, const char* cmd);
    void poll_file(STATE, CallFrame* call_frame);
    const char* extract_pid(const char* cmd, uintptr_t* pid);
    const char* extract_number(const char* cmd, uintptr_t* num,
        int (*is_digit)(int), uintptr_t (*char_to_num)(char, uintptr_t*));
    void rtrim(char* str);
    bool numeric_string(char* str);
    opcode get_opcode_ins(STATE, Tuple* tup, uint32_t idx);
    opcode get_opcode_arg(STATE, Tuple* tup, uint32_t idx);
    const char* pointer_role(Object* obj);
    void allocate_breakpoints(CompiledMethod* cm);
    const char* get_method(STATE, const char* cmd, CompiledMethod** pmeth);
    CompiledMethod* get_method(STATE, Module* mod, const char* method_name);
    const char* class_path(STATE, const char* cmd, Module** pmod);
    bool write_backtrace(STATE, CallFrame* call_frame, const char* file);

  private:
    void generate_header(STATE, CallFrame* call_frame, std::string& str);
    void generate_backtrace_frame(STATE, CallFrame* call_frame,
        uint32_t nth_frame, SelfPointers& self_pointers, std::string& str);
    void generate_stack(STATE, CallFrame* call_frame,
                        const char* spaces, std::string& str);
    void generate_locals(STATE, CallFrame* call_frame,
                         const char* spaces, std::string& str);
    void generate_ivars(STATE, CallFrame* call_frame,
                        const char* spaces, std::string& str);

  private:
    bool command_n(STATE, CallFrame* call_frame);
    bool command_s(STATE, CallFrame* call_frame);
    bool command_r(STATE, CallFrame* call_frame);
    bool command_bpc(STATE, CallFrame* call_frame, const char* cmd);
    bool command_bpi(STATE, CallFrame* call_frame, const char* cmd);
    bool command_bpr(STATE, CallFrame* call_frame);
    bool command_bpm(STATE, CallFrame* call_frame, const char* cmd);
    bool command_stk(STATE, CallFrame* call_frame);
    bool command_l(STATE, CallFrame* call_frame);
    bool command_iv(STATE, CallFrame* call_frame);
    bool command_f(STATE, CallFrame* call_frame);
    bool command_bt(STATE, CallFrame* call_frame, const char* cmd);
    bool command_t(STATE, CallFrame* call_frame, const char* cmd);

  public:
    Debugger();
    void run(STATE, CallFrame* call_frame);
  };
}

#endif

