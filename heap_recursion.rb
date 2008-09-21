# Pretty RBC
# Copyright (c) 2008 Jeremy Roach
# Licensed under The MIT License

module HeapRecursion

  def self.call_to_goto(ic, idx, ins_size)
    if ins_size >= 2
      ic.replace(idx, :goto, 99999)
      ic.delete(idx + 2, ins_size - 2)
    else
      raise "error: call_to_goto: small ins_size"
    end
  end

  # these are just the indexes that point at
  # the beginning of every iseq copy except
  # the original (at zero). they're retrieved
  # from goto's in the original iseq
  #
  def self.get_static_gotos(ic, rec_calls)
    rec_calls.inject([]) do |gotos, (i, )|
      gotos << ic.iseq[i.succ]
    end
  end

  def self.count_recursive_calls(ic)
    cnt = k = 0
    k, ins_size, = find_call(ic, k)

    until k.nil?
      cnt += 1
      k, ins_size, = find_call(ic, k + ins_size)
    end

    cnt
  end

  def self.get_iseq_start(iseq_metadata, idx)
    k = 0
    iseq_metadata.each do |(start_idx, ident)|
      break if idx < start_idx
      k = start_idx
    end
    k
  end

  def self.get_iseq_id(iseq_metadata, idx)
    k = -1
    iseq_metadata.each do |(start_idx, ident)|
      break if idx < start_idx
      k += 1
    end
    k
  end

  def self.get_iseq_metadata(static_gotos)

    iseq_metadata = [[0, 0]]
    i = 1

    static_gotos.each do |k|
      iseq_metadata << [k, i]
      i += 1
    end

    iseq_metadata   # [[start index, identifier]]
  end

  def self.insert_push_stack(ic, idx_at_goto)
    ary = []

    (0...ic.cm.local_count).each do |k|

      ary += [:push_local, k, :push_local, ic.cm.local_count,
              :send_stack, ic.literals.length, 1, :pop]
    end

    ary += [:push_int, 0, :push_local, ic.cm.local_count,
            :send_stack, ic.literals.length, 1, :pop]

    ic.insert(idx_at_goto, ary)

    idx_at_goto + ary.length + 2
  end

  def self.insert_pop_stack(ic, idx_at_ret, iseq_count)

    ary = [:push_local, ic.cm.local_count, :send_stack, ic.literals.length + 2, 0,
            :goto_if_false, 99999, :sret,
            :push_local, ic.cm.local_count, :send_stack, ic.literals.length + 1, 0,
            :set_local, ic.cm.local_count.succ, :pop]

    k = ic.cm.local_count - 1
    while k >= 0

      ary += [:push_local, ic.cm.local_count, :send_stack, ic.literals.length + 1, 0,
              :set_local, k, :pop]

      k -= 1
    end

    (0...iseq_count).each do |k|

      ary += [:push_int, k, :push_local, ic.cm.local_count.succ,
              :send_stack, ic.literals.length + 3, 1,
              :goto_if_false, 99999, :goto, 99999]
    end

    ic.insert(idx_at_ret.succ, ary)
    ic.delete(idx_at_ret)

    idx_at_ret + ary.length + 1
  end

  def self.insert_init_stack(ic)
    ic.immutable_gotos = []
    ic.insert(0, [:make_array, 0, :set_local, ic.cm.local_count, :pop])

    ic.cm.local_count += 2
    ic.local_names << :__stack__
    ic.local_names << :__iseq_id__
  end

  def self.insert_send_sites(ic)
    ic.literals << SendSite.new(:<<)
    ic.literals << SendSite.new(:pop)
    ic.literals << SendSite.new(:empty?)
    ic.literals << SendSite.new(:==)
  end

  def self.modify_iseq_copy(ic, num_args, static_gotos, original_lengths)

    len_orig_iseq, len_orig_exc, len_orig_lines = original_lengths
    ic.immutable_gotos = static_gotos

    len_iseq = ic.iseq.length
    len_exc = ic.exceptions.length
    len_lines = ic.lines.length

    ic.duplicate_iseq(0...len_orig_iseq)
    ic.offset_gotos(len_iseq...ic.iseq.length)

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

    ic.normalize_gotos
  end

  def self.modify_original_iseq(ic)

    rec_calls = []
    k = 0
    iseq_count = count_recursive_calls(ic).succ

    loop do

      idx_call, ins_size, num_args = find_call(ic, k)
      idx_ret = find_instruction(ic, :sret, k)

      if idx_call.nil? and (rec_calls.empty? or idx_ret.nil?)
        break
      end

      if idx_ret.nil? or (!idx_call.nil? and idx_call < idx_ret)

        call_to_goto(ic, idx_call, ins_size)
        k = insert_push_stack(ic, idx_call)
        idx_call = find_instruction(ic, :goto, idx_call)
        rec_calls << [idx_call, num_args]

      else
        k = insert_pop_stack(ic, idx_ret, iseq_count)
      end
    end

    rec_calls
  end

  def self.modify_iseq_identifiers(ic, static_gotos)

    iseq_metadata = get_iseq_metadata(static_gotos)

    i = 0
    while i
      if ic.iseq[i] == :goto
        if static_gotos.include? ic.iseq[i.succ]
          k = i
          while k
            if ic.iseq[k] == :push_int
              iseq_id = get_iseq_id(iseq_metadata, k)
              ic.iseq[k.succ] = iseq_id
              break
            end
            k = ic.previous(k)
          end
        end
      end
      i = ic.next(i)
    end
  end

  def self.fill_goto_for_resumption(ic, iseq_metadata, target_iseq_id, idx_at_goto)

    idx_at_iseq_start = get_iseq_start(iseq_metadata, idx_at_goto)

    iseq_metadata.each do |(idx, ident)|
      if ident == target_iseq_id
        i = idx
        while i
          if ic.iseq[i] == :goto
            k = ic.iseq[i.succ]
            if k == idx_at_iseq_start
              ic.iseq[idx_at_goto.succ] = i.succ.succ
              break
            end
          end
          i = ic.next(i)
        end
        break
      end
    end
  end

  def self.modify_resumption_gotos(ic, rec_calls, static_gotos)
    iseq_id = 0
    iseq_count = rec_calls.length.succ
    iseq_metadata = get_iseq_metadata(static_gotos)

    i = 0
    while i
      if ic.iseq[i] == :sret
        ic.iseq[i - 1] = i.succ

        k = i.succ
        while k
          if iseq_id == iseq_count
            iseq_id = 0
            break
          elsif ic.iseq[k] == :goto
            fill_goto_for_resumption(ic, iseq_metadata, iseq_id, k)
            ic.iseq[k - 1] = k.succ.succ
            iseq_id += 1
          end
          k = ic.next(k)
        end
        i = k
      else
        i = ic.next(i)
      end
    end
  end

  def self.modify_instructions(ic)

    rec_calls = modify_original_iseq(ic)

    return if rec_calls.empty?

    len_orig_iseq = ic.iseq.length
    len_orig_exc = ic.exceptions.length
    len_orig_lines = ic.lines.length

    original_lengths = [len_orig_iseq, len_orig_exc, len_orig_lines]

    rec_calls.each do |(idx, num_args)|
      ic.iseq[idx.succ] = ic.iseq.length
      modify_iseq_copy(ic, num_args, [], original_lengths)
    end

    ic.iseq = ic.iseq[0...len_orig_iseq]
    ic.exceptions = ic.exceptions[0...len_orig_exc]
    ic.lines = ic.lines[0...len_orig_lines]

    static_gotos = get_static_gotos(ic, rec_calls)

    rec_calls.each do |(idx, num_args)|
      modify_iseq_copy(ic, num_args, static_gotos, original_lengths)
    end

    modify_iseq_identifiers(ic, static_gotos)
    modify_resumption_gotos(ic, rec_calls, static_gotos)

    insert_init_stack(ic)
    insert_send_sites(ic)
  end

  def self.find_call(ic, start_at = 0)
    i = start_at

    while i
      if ic.iseq[i] == :send_stack and
            ic.cm.name == ic.literals[ic.iseq[i.succ]].name
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

  def self.find_instruction(ic, ins, start_at = 0)
    i = start_at

    while i
      if ic.iseq[i] == ins
        break
      end
      i = ic.next(i)
    end

    i
  end

  def self.optimize(cm_main)

    for cm in cm_main.all_methods
      ic = InstructionChanges.new(cm)
      modify_instructions(ic)
      ic.finalize
    end
  end
end

