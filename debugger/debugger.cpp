
#include "builtin/module.hpp"
#include "builtin/class.hpp"
#include "builtin/symbol.hpp"
#include "builtin/fixnum.hpp"

#include "debugger.hpp"

namespace rubinius {

  Debugger::Debugger()
    : num_records(0)
    , options(0)
    , read_file(NULL)
    , write_file(NULL)
    , instruction_count(0)
    , bp_instruction_count(0)
  {
    pthread_mutex_init(&mutex, NULL);
  }

  void Debugger::run(STATE, CallFrame* call_frame) {
    CompiledMethod* cm = call_frame->cm;
    int ip = call_frame->ip - 1;
    uint32_t num_ops = cm->iseq()->opcodes()->num_fields();

    // must not call any code that acquires the global_lock
    // in the following section so there's no opportunity for deadlock

    pthread_mutex_lock(&mutex);

    if(!(options & NO_DEBUG_DIR)) {

      ++instruction_count;

      allocate_breakpoints(cm);

      if(instruction_count == bp_instruction_count ||
            (cm->breakpoints[ip] != 0 &&
            ((cm->breakpoints[ip] & NEXT_BREAKPOINT) ||
            ((cm->breakpoints[ip] & STEP_BREAKPOINT) &&
            !(options & IGNORE_STEP_BREAKPOINT)) ||
            ((cm->breakpoints[ip] & CUSTOM_BREAKPOINT) &&
            !(options & IGNORE_CUSTOM_BREAKPOINT))))) {

        if(cm->breakpoints[ip] & NEXT_BREAKPOINT) {
          uint32_t k;
          for(k = 0; k < num_ops; k++) {
            cm->breakpoints[k] &= ~NEXT_BREAKPOINT;
          }
        }

        options &= ~IGNORE_STEP_BREAKPOINT;
        options &= ~IGNORE_CUSTOM_BREAKPOINT;

        set_files();
        write_header(state, call_frame);
        poll_file(state, call_frame);
      }
    }

    pthread_mutex_unlock(&mutex);
  }

  void Debugger::set_files() {
    char* tmp;

    if(!read_file && !write_file) {

      tmp = getenv("RBX_DEBUG_DIR");

      if(tmp) {
        size_t len = strlen(tmp);
        char* rfile = new char[len+25];
        char* wfile = new char[len+25];

        strcpy(rfile, tmp);
        strcpy(wfile, tmp);

        if(len > 0 && tmp[len - 1] != '/') {
          rfile[len] = '/';
          wfile[len] = '/';
          ++len;
        }
        strcpy(rfile + len, "rbx_read.txt");
        strcpy(wfile + len, "rbx_write.txt");
        read_file = rfile;
        write_file = wfile;
      }
      else {
        options |= NO_DEBUG_DIR;
      }
    }
  }

  void Debugger::write_record(const char* out) {
    FILE* wd;
    char ssz[32];
    std::string str;

    if(!write_file) return;
    if((wd = fopen(write_file, "a")) == NULL) return;

    snprintf(ssz, sizeof(ssz), "%u\n", strlen(out));
    str += ssz;
    str += out;

    fwrite(str.c_str(), 1, str.size(), wd);
    fclose(wd);
  }

  void Debugger::write_header(STATE, CallFrame* call_frame) {
    Object* self = call_frame->scope->self();
    CompiledMethod* cm = call_frame->cm;
    int ip = call_frame->ip - 1;
    std::string str;
    char tmp[2048];
    opcode op = get_opcode(state, cm->iseq()->opcodes(), ip + 1);

    snprintf(tmp, sizeof(tmp), "[debug] process id: %p, thread id: %p,\n"
                            "        self pointer: %p, method pointer: %p,\n"
                            "        sp: %d, ip: %d, instruction: '%s'\n",
        (void*)getpid(), (void*)pthread_self(), self, cm,
        call_frame->calculate_sp(), ip + 1,
        InstructionSequence::get_instruction_name(op));
    str += tmp;

    if(kind_of<Class>(self) || kind_of<Module>(self)) {

      if(static_cast<Module*>(self)->name() &&
          !static_cast<Module*>(self)->name()->nil_p()) {
        snprintf(tmp, sizeof(tmp), "        self class name: '%s'\n",
            static_cast<Module*>(self)->name()->c_str(state));
        str += tmp;
      }
    }
    else {
      if(self->class_object(state)->name() &&
          !self->class_object(state)->name()->nil_p()) {
        snprintf(tmp, sizeof(tmp), "        self class name: '%s'\n",
            self->class_object(state)->name()->c_str(state));
        str += tmp;
      }
    }

    if(cm->name() && !cm->name()->nil_p()) {
      snprintf(tmp, sizeof(tmp), "        method name: '%s'\n", cm->name()->c_str(state));
      str += tmp;
    }

    if(!cm->backend_method_) {
      snprintf(tmp, sizeof(tmp), "        backend_method_ is NULL\n");
      str += tmp;
    }

    write_record(str.c_str());
  }

  void Debugger::poll_file(STATE, CallFrame* call_frame) {
    FILE* rd;
    uint32_t nth_record, sec_sleep = 1;
    int sz_record;
    char tmp[1024];

    if(!read_file) return;

    while(1) {

      if((rd = fopen(read_file, "r")) == NULL) {
        sleep(sec_sleep);
        continue;
      }

      nth_record = 0;

      while(1) {

        if(fgets(tmp, sizeof(tmp), rd) == NULL) {
          sleep(sec_sleep);
          break;
        }

        rtrim(tmp);

        if(!numeric_string(tmp)) {
          sleep(sec_sleep);
          break;
        }

        sz_record = atoi(tmp);
        if(sz_record <= 0) continue;

        if(sz_record >= (int)sizeof(tmp)) {
          sleep(sec_sleep);
          break;
        }

        tmp[sz_record] = '\0';
        if(fread(tmp, 1, (size_t)sz_record, rd) < (size_t)sz_record) {
          sleep(sec_sleep);
          break;
        }

        if(nth_record >= num_records) {
          ++num_records;
          if(execute_command(state, call_frame, tmp)) {
            fclose(rd);
            return;
          }
        }

        ++nth_record;
      }

      fclose(rd);
    }
  }

  bool Debugger::execute_command(STATE, CallFrame* call_frame, const char* cmd) {
    int ip = call_frame->ip - 1;
    CompiledMethod* cm = call_frame->cm;
    Tuple* ops = cm->iseq()->opcodes();
    opcode op = get_opcode(state, ops, ip + 1);
    uint32_t num_ops = ops->num_fields();
    size_t ins_size = InstructionSequence::instruction_width(op);
    uintptr_t pid;

    cmd = extract_pid(cmd, &pid);
    if(pid != 0 && pid != (uintptr_t)getpid()) return false;

    if(strcmp(cmd, "n") == 0) {
      opcode jip;

      switch(op) {
      case InstructionSequence::insn_goto_if_false:
      case InstructionSequence::insn_goto_if_true:
      case InstructionSequence::insn_goto_if_defined:
      case InstructionSequence::insn_goto:
        jip = static_cast<Fixnum*>(ops->at(state, ip + 2))->to_native();
        if(jip < num_ops) {
          cm->breakpoints[jip] |= NEXT_BREAKPOINT;
          options |= IGNORE_STEP_BREAKPOINT;
        }
      }
      if(ip + ins_size + 1 < num_ops) {
        cm->breakpoints[ip + ins_size + 1] |= NEXT_BREAKPOINT;
        options |= IGNORE_STEP_BREAKPOINT;
      }
      options |= IGNORE_CUSTOM_BREAKPOINT;
    }
    else if(strcmp(cmd, "s") == 0) {
      options |= IGNORE_CUSTOM_BREAKPOINT;
    }
    else if(strcmp(cmd, "r") == 0) {
      options |= IGNORE_STEP_BREAKPOINT;
    }
    else if(strncmp(cmd, "bpc", 3) == 0) {
      uint32_t offset;
      if(extract_number(cmd, &offset)) {
        bp_instruction_count = instruction_count + offset;
        options |= IGNORE_STEP_BREAKPOINT;
        options |= IGNORE_CUSTOM_BREAKPOINT;
      }
      else {
        write_record("[debug] offset not given for bpc command\n");
        return false;
      }
    }
    else if(strncmp(cmd, "bpi", 3) == 0) {
      uint32_t bpip, ydip = 0, k, nth_ins = 0;
      opcode oc;

      if(extract_number(cmd, &bpip)) {
        for(k = 0; k < num_ops; nth_ins++) {
          if(bpip <= k) {
            if(bpip == k && nth_ins % 2 == 0) ydip = k;
            break;
          }
          if(nth_ins % 2 == 0) ydip = k;
          oc = get_opcode(state, ops, k);
          k += InstructionSequence::instruction_width(oc);
        }
        cm->breakpoints[ydip] ^= CUSTOM_BREAKPOINT;
        if(cm->breakpoints[ydip] & CUSTOM_BREAKPOINT)
          write_record("[debug] breakpoint set\n");
        else
          write_record("[debug] breakpoint unset\n");
      }
      else {
        write_record("[debug] ip not given for bpi command\n");
      }
      return false;
    }
    else if(strcmp(cmd, "bpr") == 0) {
      CallFrame* frm = call_frame->previous;

      if(frm && frm->cm && frm->cm->breakpoints &&
            (uint32_t)frm->ip < frm->cm->iseq()->opcodes()->num_fields()) {
        frm->cm->breakpoints[frm->ip] ^= CUSTOM_BREAKPOINT;
        if(frm->cm->breakpoints[frm->ip] & CUSTOM_BREAKPOINT)
          write_record("[debug] breakpoint set\n");
        else
          write_record("[debug] breakpoint unset\n");
      }
      return false;
    }
    else if(strncmp(cmd, "bpm", 3) == 0) {
      CompiledMethod* meth = get_method(state, cmd + 3);
      if(meth) {
        allocate_breakpoints(meth);
        meth->breakpoints[0] ^= CUSTOM_BREAKPOINT;
        if(meth->breakpoints[0] & CUSTOM_BREAKPOINT)
          write_record("[debug] breakpoint set\n");
        else
          write_record("[debug] breakpoint unset\n");
      }
      else {
        write_record("[debug] method not found\n");
      }
      return false;
    }
    else if(strcmp(cmd, "stk") == 0) {
      std::string str = "[debug] stack\n";
      int sp = call_frame->calculate_sp();
      char tmp[256];

      for(; sp >= 0; sp--) {
        snprintf(tmp, sizeof(tmp), "%d: %p (%s)\n",
            sp, call_frame->stack_at((size_t)sp),
            pointer_role(call_frame->stack_at((size_t)sp)));
        str += tmp;
      }
      if(str.size() > 14)
        write_record(str.c_str());

      return false;
    }
    else if(strcmp(cmd, "l") == 0) {
      VariableScope* scp = call_frame->scope;
      int num_locals = scp->number_of_locals();
      int i;
      char tmp[256];
      std::string str = "[debug] locals\n";

      for(i = 0; i < num_locals; i++) {
        snprintf(tmp, sizeof(tmp), "%d: %p (%s)\n", i, scp->get_local(i),
            pointer_role(scp->get_local(i)));
        str += tmp;
      }
      if(str.size() > 15)
        write_record(str.c_str());

      return false;
    }
    else if(strcmp(cmd, "f") == 0) {
      uint32_t frame_count = 0;
      CallFrame* frm = call_frame;
      char tmp[256];
      std::string str = "[debug] call frame\n";

      while(frm) {
        ++frame_count;
        frm = frm->previous;
      }

      snprintf(tmp, sizeof(tmp), "frames: %u\n", frame_count);
      str += tmp;
      snprintf(tmp, sizeof(tmp), "args: %d\n", call_frame->args);
      str += tmp;
      snprintf(tmp, sizeof(tmp), "stack size: %d\n", call_frame->stack_size);
      str += tmp;
      snprintf(tmp, sizeof(tmp), "locals: %d\n", call_frame->scope->number_of_locals());
      str += tmp;
      snprintf(tmp, sizeof(tmp), "unwind: %d\n", call_frame->current_unwind);
      str += tmp;
      snprintf(tmp, sizeof(tmp), "opcodes: %u\n", num_ops);
      str += tmp;

      write_record(str.c_str());
      return false;
    }
    else {
      write_record("[debug] command not recognized\n");
      return false;
    }

    return true;  // don't read anymore commands
  }

  // expects the pid to be at the beginning of the string
  // and to be hex characters (with or without a '0x' prefix).
  // returns the start of the command after the pid
  //
  const char* Debugger::extract_pid(const char* cmd, uintptr_t* pid) {
    const char* p = cmd;
    const char* strt = cmd;
    const char* hex = cmd;
    uintptr_t pow16 = 1;
    *pid = 0;

    while(*p) {
      if(*p == ' ') {
        hex = p - 1;
        while(*p == ' ') ++p;
        if(*p) strt = p;
        break;
      }
      ++p;
    }

    if(hex >= cmd && *hex) {
      do {
        if(*hex >= '0' && *hex <= '9') {
          *pid += (uintptr_t)(*hex - '0') * pow16;
          pow16 *= 16;
        }
        else if(*hex >= 'a' && *hex <= 'f') {
          *pid += (uintptr_t)(*hex - 'W') * pow16;
          pow16 *= 16;
        }
        else if(*hex >= 'A' && *hex <= 'F') {
          *pid += (uintptr_t)(*hex - '7') * pow16;
          pow16 *= 16;
        }
        --hex;
      } while(hex >= cmd);
      return strt;
    }

    return cmd;
  }

  // base 10 natural number delimited by string boundary and/or spaces
  // returns the pointer to the next token or null byte if found
  //
  const char* Debugger::extract_number(const char* cmd, uint32_t* num) {
    const char* rght = cmd;
    const char* lft = NULL;
    uint32_t digits = 0;
    uint32_t pow10 = 1;
    *num = 0;

    while(*rght) {

      if(*rght == ' ') {
        if(digits > 0) {
          while(*rght == ' ') ++rght;
          break;
        }
      }
      else {
        if(isdigit(*rght) &&
              (rght == cmd || isdigit(*(rght - 1)) || *(rght - 1) == ' ')) {
          ++digits;
          lft = rght;
        }
        else {
          digits = 0;
        }
      }

      ++rght;
    }

    if(digits > 0) {
      while(lft >= cmd && isdigit(*lft)) {
        *num += (uint32_t)(*lft - '0') * pow10;
        pow10 *= 10;
        --lft;
      }
      return rght;
    }

    return NULL;    // not found
  }

  void Debugger::rtrim(char* str) {   // don't use if strlen can equal 0
    while(*str) ++str;
    --str; *str = '\0';
  }

  bool Debugger::numeric_string(char* str) {
    if(!*str) return false;
    while(*str) {
      if(!isdigit(*str)) return false;
      ++str;
    }
    return true;
  }

  // only use with instruction opcode, not the arg opcodes
  //
  opcode Debugger::get_opcode(STATE, Tuple* tup, uint32_t idx) {
    return tup->at(state, idx)->nil_p() ? 0 :
        static_cast<Fixnum*>(tup->at(state, idx))->to_native();
  }

  const char* Debugger::pointer_role(Object* obj) {
    if(FIXNUM_P(obj))
      return "fixnum";
    else if(REFERENCE_P(obj))
      return "reference";
    else if(SYMBOL_P(obj))
      return "symbol";
    else if(FALSE_P(obj))
      return "false";
    else if(NIL_P(obj))
      return "nil";
    else if(TRUE_P(obj))
      return "true";
    else if(UNDEF_P(obj))
      return "undef";
    else
      return "unknown";
  }

  void Debugger::allocate_breakpoints(CompiledMethod* cm) {
    if(!cm->breakpoints) {
      uint32_t num_ops = cm->iseq()->opcodes()->num_fields();
      cm->breakpoints = new uint8_t[num_ops];   // optimize this to 3 bits
      memset(cm->breakpoints, 0, num_ops);      // per opcode
      cm->breakpoints[0] = STEP_BREAKPOINT;     /* never unset this */
    }
  }

  CompiledMethod* Debugger::get_method(STATE, const char* cmd) {
    return NULL;
  }
}

