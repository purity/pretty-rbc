
# prints to STDOUT the indexes of send instructions before each is executed.
# it's probably good to be cautious about using this to debug IO problems.
#
# 1. add instruction_changes.rb, pcm.rb, and print_debug.rb to kernel/compiler or
#    InstructionChanges and PrintDebug to kernel/compiler/compiled_file.rb or wherever
# 2. add something like these to CompiledFile.dump or Compiler.compile_file/string:
#
#    if /common\/io\.rb/.match(file)
#      PrintDebug.run(cm, [], [:sysread])
#    end
#
#    PrintDebug.run(cm)
#    str = PrettyCM.dump(cm)
#    fly = cm.file.to_s
#    PrettyCM.write_file(fly + '.pcm', str) if fly != ''
#
module PrintDebug

  SLOT_FOR_SEND_INDEX = 34

  def self.all_methods(obj)
    case obj
    when CompiledMethod
      cmethods = [obj]
      obj.literals.each do |o|
        cmethods += all_methods(o)
      end
      cmethods
    else
      []
    end
  end

  def self.modify_instructions(ic)

    # have i already modified this compiled method?
    if ic.iseq[0] == :push_true and ic.iseq[1] == :pop
      return
    end

    ic.insert(0, [:push_true, :pop])

    if ic.cm.stack_size >= 0
      ic.cm.stack_size += 3
    end

    ic.literals << SendSite.new(:class)
    ic.literals << "file: [#{ic.cm.file}]"
    ic.literals << "method: [#{ic.cm.name}]"
    ic.literals << SendSite.new(:puts)
    ic.literals << :STDOUT
    ic.literals << nil
    lit_len = ic.literals.length

    ary = [:push_const_fast, lit_len - 2, lit_len - 1, :push_literal, lit_len - 5,
             :string_dup, :send_stack, lit_len - 3, 1, :pop,
           :push_const_fast, lit_len - 2, lit_len - 1, :push_literal, lit_len - 4,
             :string_dup, :send_stack, lit_len - 3, 1, :pop,
           :push_const_fast, lit_len - 2, lit_len - 1, :push_self,
             :send_method, lit_len - 6, :send_stack, lit_len - 3, 1, :pop,
           :push_const_fast, lit_len - 2, lit_len - 1, :push_int, 0,
             :send_stack, lit_len - 3, 1, :pop]

    i = 0
    while i
      ins_str = ic.iseq[i].to_s
      if /send/ =~ ins_str

        v = i
        k = ic.previous(i)
        while k
          ins_str_prev = ic.iseq[k].to_s

          if /allow_private|set_call_flags/ =~ ins_str_prev
            v = k
            k = ic.previous(k)
          else
            k = nil
          end
        end

        i = v + ary.size + (i - v)
        ary[SLOT_FOR_SEND_INDEX] = i
        ic.insert(v, ary)
      end
      i = ic.next(i)
    end

    ic.finalize
  end

  def self.run(cm_main, excluded_methods = [], included_methods = [])   # symbol names

    for cm in all_methods(cm_main)

      # (include all and exclude some or none) or
      # exclude all except some

      if (included_methods.empty? and !excluded_methods.include?(cm.name)) or
            (excluded_methods.empty? and included_methods.include?(cm.name))
        ic = InstructionChanges.new(cm)
        modify_instructions(ic)
      end
    end

    cm_main
  end
end

