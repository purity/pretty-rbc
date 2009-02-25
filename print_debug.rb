
# prints to STDERR the indexes of send instructions before each is executed.
# it's probably good to be cautious about using this to debug IO problems.
#
# 1. add instruction_changes.rb and print_debug.rb to kernel/delta or
#    InstructionChanges and PrintDebug to kernel/compiler/compiled_file.rb or wherever
# 2. add something like this to Compiler.compile_file/string or CompiledFile.dump:
#
#    if /common\/io\.rb/.match(cm.file.to_s)
#      PrintDebug.run(cm, [], [:sysread])
#    end
#
module PrintDebug

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

    ic.literals << "[#{ic.cm.file}]"
    ic.literals << "[#{ic.cm.name}]"
    ic.literals << SendSite.new(:puts)
    ic.literals << :STDERR
    ic.literals << nil
    lit_len = ic.literals.length

    ic.insert(0, [:push_const_fast, lit_len - 2, lit_len - 1, :push_literal, lit_len - 5,
                  :string_dup, :send_stack, lit_len - 3, 1, :pop])

    ic.insert(10, [:push_const_fast, lit_len - 2, lit_len - 1, :push_literal, lit_len - 4,
                   :string_dup, :send_stack, lit_len - 3, 1, :pop])

    i = 20

    while i
      ins_str = ic.iseq[i].to_s
      if /send/.match(ins_str)
        ic.insert(i, [:push_const_fast, lit_len - 2, lit_len - 1, :push_int, i + 9,
                      :send_stack, lit_len - 3, 1, :pop])
        i += 9
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

