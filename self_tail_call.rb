
module SelfTailCall

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

  def self.call_to_goto(ic, idx, ins_size)
    if ins_size >= 2
      ic.replace(idx, :goto, 99999)
      ic.delete(idx + 2, ins_size - 2)
    else
      raise "error: call_to_goto: small ins_size"
    end
  end

  def self.get_arg_counts(tail_calls)
    tail_calls.inject([]) do |arg_counts, info|
      arg_counts << info[1]
    end
  end

  def self.modify_original_iseq(ic)

    tail_calls = []
    idx, ins_size, num_args = find(ic)

    until idx.nil?
      tail_calls << [idx, num_args]
      call_to_goto(ic, idx, ins_size)
      idx, ins_size, num_args = find(ic, idx)
    end

    tail_calls
  end

  def self.modify_iseq_copy(ic, num_args, uniq_arg_counts, original_lengths)

    len_orig_iseq, len_orig_exc, len_orig_lines = original_lengths

    ic.immutable_iseq_refs = []
    uniq_arg_counts.each_value do |v|
      ic.immutable_iseq_refs << v
    end

    len_iseq = ic.iseq.length
    len_exc = ic.exceptions.length
    len_lines = ic.lines.length

    ic.duplicate_iseq(0...len_orig_iseq)
    ic.offset_iseq_refs(len_iseq...ic.iseq.length)

    ic.duplicate_exceptions(0...len_orig_exc)
    ic.offset_exceptions(len_exc...ic.exceptions.length, len_iseq)

    ic.duplicate_lines(0...len_orig_lines)
    ic.offset_lines(len_lines...ic.lines.length, len_iseq)

    i = len_iseq
    while i
      if ic.iseq[i] == :passed_arg
        k = ic.iseq[i.succ]
        ic.delete(i.succ)

        if k < num_args
          ic.replace(i, :push_true)
        else
          ic.replace(i, :push_false)
        end

      elsif ic.iseq[i] == :set_local_from_fp
        ic.replace(i, :set_local)
        ic.replace(i + 2, :pop)
      end
      i = ic.next(i)
    end

    ic.normalize_iseq_refs
  end

  def self.modify_instructions(ic)

    tail_calls = modify_original_iseq(ic)

    return if tail_calls.empty?

    arg_counts = get_arg_counts(tail_calls)
    uniq_arg_counts = {}

    len_orig_iseq = ic.iseq.length
    len_orig_exc = ic.exceptions.length
    len_orig_lines = ic.lines.length

    original_lengths = [len_orig_iseq, len_orig_exc, len_orig_lines]

    tail_calls.each do |(idx, num_args)|
      if uniq_arg_counts[num_args]
        ic.iseq[idx.succ] = uniq_arg_counts[num_args]
      else
        uniq_arg_counts[num_args] = ic.iseq.length
        ic.iseq[idx.succ] = uniq_arg_counts[num_args]
        modify_iseq_copy(ic, num_args, uniq_arg_counts, original_lengths)
      end
    end

    ic.iseq = ic.iseq[0...len_orig_iseq]
    ic.exceptions = ic.exceptions[0...len_orig_exc]
    ic.lines = ic.lines[0...len_orig_lines]

    arg_counts.uniq.each do |num_args|
      modify_iseq_copy(ic, num_args, uniq_arg_counts, original_lengths)
    end

    ic.finalize
  end

  def self.to_return?(iseq, k)
    case iseq[k]
    when :goto
      to_return?(iseq, iseq[k.succ])
    when :ret
      true
    else
      false
    end
  end

  def self.find(ic, start_at = 0)
    i = start_at

    while i
      if ic.iseq[i] == :send_stack and
            ic.cm.name == ic.literals[ic.iseq[i.succ]].name and
            to_return?(ic.iseq, ic.next(i))
        num_args = ic.iseq[i + 2]
        back1 = ic.previous(i)
        back2 = ic.previous(back1)

        if ic.iseq[back1] == :push_self
          return [back1, 4, num_args]
        elsif ic.iseq[back1] == :set_call_flags and ic.iseq[back2] == :push_self
          return [back2, 6, num_args]
        end
      end
      i = ic.next(i)
    end

    [nil, nil, nil]
  end

  def self.optimize(cm_main)

    for cm in all_methods(cm_main)
      ic = InstructionChanges.new(cm)
      modify_instructions(ic)
    end

    cm_main
  end
end

