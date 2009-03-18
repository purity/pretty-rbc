
module YieldDebugger

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

    if ic.iseq[0] == :yield_debugger
      return
    end

    ic.insert(0, [:yield_debugger])

    i = ic.next(1)
    while i
      if ic.next(i)
        ic.insert(ic.next(i), [:yield_debugger])
      else
        ic.insert(-1, [:yield_debugger])
      end
      ic.swap(i)
      i = ic.next(i.succ)
    end

    ic.finalize
  end

  def self.run(cm_main)

    for cm in all_methods(cm_main)
      ic = InstructionChanges.new(cm)
      modify_instructions(ic)
    end

    cm_main
  end
end

