
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

  # STDOUT.puts "file"
  # STDOUT.puts "method"
  # if self.kind_of? Class or self.kind_of? Module
  #   STDOUT.puts self
  # else
  #   STDOUT.puts self.class
  # end
  # STDOUT.puts 0   # send index

  PRINT_INSTRUCTIONS = [
    :push_const_fast, 0, 1,
    :push_literal, 4,
    :string_dup,
    :send_stack, 2, 1,
    :pop,
    :push_const_fast, 0, 1,
    :push_literal, 3,
    :string_dup,
    :send_stack, 2, 1,
    :pop,
    :push_self,
    :push_const_fast, 9, 10,
    :send_stack, 6, 1,
    :dup_top,
    :goto_if_true, 38,
    :pop,
    :push_self,
    :push_const_fast, 7, 8,
    :send_stack, 6, 1,
    :goto_if_false, 49,
    :push_const_fast, 0, 1,
    :push_self,
    :send_stack, 2, 1,
    :goto, 58,
    :push_const_fast, 0, 1,
    :push_self,
    :send_method, 5,
    :send_stack, 2, 1,
    :pop,
    :push_const_fast, 0, 1,
    :push_int, 0,
    :send_stack, 2, 1,
    :pop
  ]

  OFFSET_FOR_SEND_INDEX = 63

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

    lit_len = ic.literals.length

    ic.literals << :STDOUT
    ic.literals << nil
    ic.literals << SendSite.new(:puts)
    ic.literals << "method: [#{ic.cm.name}]"
    ic.literals << "file: [#{ic.cm.file}]"
    ic.literals << SendSite.new(:class)
    ic.literals << SendSite.new(:kind_of?)
    ic.literals << :Module
    ic.literals << nil
    ic.literals << :Class
    ic.literals << nil

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

        prnt_sz = PRINT_INSTRUCTIONS.size
        i = v + prnt_sz + (i - v)

        ic.insert(v, PRINT_INSTRUCTIONS)
        ic.offset_iseq_refs(v...(v + prnt_sz))
        ic.offset_literals(v...(v + prnt_sz), lit_len)

        ic.replace(v + OFFSET_FOR_SEND_INDEX, i)
      end
      i = ic.next(i)
    end

    ic.normalize_iseq_refs
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

