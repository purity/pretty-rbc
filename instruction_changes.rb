
# ISSUES
#   * stack_size not automatically recalculated
#
class InstructionChanges

  attr_accessor :cm
  attr_accessor :iseq
  attr_accessor :literals
  attr_accessor :local_names
  attr_accessor :lines

  attr_accessor :immutable_iseq_refs
  attr_accessor :never_shrink

  ISEQ_REF_OFFSET = 100_000_000

  INSTRUCTIONS_WITH_LOCAL = {
    :push_local => 0, :push_local_depth => 1, :set_local => 0,
    :set_local_depth => 1
  }

  INSTRUCTIONS_WITH_LITERAL = {
    :add_method => 0, :attach_method => 0, :check_serial => 0,
    :create_block => 0, :find_const => 0, :open_class => 0,
    :open_class_under => 0, :open_module => 0, :open_module_under => 0,
    :push_const => 0, :push_ivar => 0, :push_literal => 0,
    :send_method => 0, :send_stack => 0, :send_stack_with_block => 0,
    :send_stack_with_splat => 0, :send_super_stack_with_block => 0,
    :send_super_stack_with_splat => 0, :set_const => 0, :set_const_at => 0,
    :set_ivar => 0, :set_literal => 0, :dummy => 1
  }

  INSTRUCTIONS_WITH_LITERALS = {
    :push_const_fast => true
  }

  INSTRUCTIONS_WITH_ISEQ_REF = {
    :goto => 0, :goto_if_true => 0, :goto_if_false => 0,
    :goto_if_defined => 0, :setup_unwind => 0, :dinosaur => 1
  }

  def initialize(cm)
    @cm = cm
    @iseq = cm.iseq.decode.flatten
    @literals = cm.literals.to_a
    @local_names = cm.local_names.to_a
    @lines = cm.lines.to_a

    @immutable_iseq_refs = []
    @never_shrink = true
  end

  def finalize
    icc = InstructionChanges
    encoder = Rubinius::InstructionSequence::Encoder.new
    layered_iseq = icc.wrap(@iseq)

    @cm.iseq = encoder.encode_stream(layered_iseq)
    @cm.literals = icc.to_tup(@literals)
    @cm.local_names = icc.to_tup(@local_names)
    @cm.lines = icc.to_tup(@lines)
  end

  def at_ins_with_iseq_ref?(i)
    INSTRUCTIONS_WITH_ISEQ_REF[@iseq[i]]
  end

  def at_ins_with_local?(i)
    INSTRUCTIONS_WITH_LOCAL[@iseq[i]]
  end

  def at_ins_with_literal?(i)
    INSTRUCTIONS_WITH_LITERAL[@iseq[i]]
  end

  def at_ins_with_literals?(i)
    INSTRUCTIONS_WITH_LITERALS[@iseq[i]]
  end

  def previous(i)
    return nil if i == 0
    k = i - 1
    k -= 1 while @iseq[k].kind_of? Integer
    k
  end

  def next(i)
    k = i + 1
    return nil if k >= @iseq.length
    while @iseq[k].kind_of? Integer
      k += 1
      return nil if k >= @iseq.length
    end
    k
  end

  def insert(i, values)
    oldsize = @iseq.length

    if i < 0
      i += oldsize.succ
    end

    @iseq.insert(i, *values)

    newsize = @iseq.length
    size_diff = newsize - oldsize

    recalculate_iseq_refs(:insert, i, size_diff)
    recalculate_lines(:insert, i, size_diff)
  end

  def replace(i, *values)
    if i < 0 or i + values.length > @iseq.length
      raise "error: replace: out of bounds"
    end

    values.each_index do |k|
      @iseq[i] = values[k]
      i += 1
    end
  end

  def delete(i, ins_size = nil)
    oldsize = @iseq.length

    if i < 0
      i += oldsize
    end

    if @never_shrink

      if ins_size
        k = i + ins_size
        while i < k
          @iseq[i] = :noop
          i += 1
        end
      elsif @iseq[i].kind_of? Integer
        @iseq[i] = :noop
      else
        k = i
        while i == k or @iseq[i].kind_of? Integer
          @iseq[i] = :noop
          i += 1
        end
      end
    else

      if ins_size
        ins_size.times { @iseq.delete_at(i) }
      elsif @iseq[i].kind_of? Integer
        @iseq.delete_at(i)
      else
        @iseq.delete_at(i)
        @iseq.delete_at(i) while @iseq[i].kind_of? Integer
      end

      newsize = @iseq.length
      size_diff = oldsize - newsize

      recalculate_iseq_refs(:delete, i, size_diff)
      recalculate_lines(:delete, i, size_diff)
    end
  end

  def swap(i)

    raise "error: swap: no Symbol at 'i'" unless
      @iseq[i].kind_of? Symbol

    k = self.next(i)
    raise "error: swap: no ins after 'i'" if k.nil?

    n = k.succ
    n += 1 while @iseq[n].kind_of? Integer

    size_i = k - i
    size_k = n - k

    values_i = @iseq[i,size_i]
    values_k = @iseq[k,size_k]

    replace(i, *values_k)
    replace(i + size_k, *values_i)

    if size_i != size_k
      x = i + size_k

      @iseq.each_index do |n|
        if arg_idx = at_ins_with_iseq_ref?(n)
          if @iseq[n.succ + arg_idx] == k
            @iseq[n.succ + arg_idx] = x
          end
        end
      end

      recalculate_lines(:swap, i, size_i + size_k)
    end
  end

  def recalculate_iseq_refs(action, i, size_diff)
    return if size_diff == 0
    k = i + (size_diff - 1)

    @iseq.each_index do |n|

      if arg_idx = at_ins_with_iseq_ref?(n)
        x = @iseq[n.succ + arg_idx]
        unless @immutable_iseq_refs.include? x
          case action
          when :delete
            if normalized_iseq_ref(x) > k
              @iseq[n.succ + arg_idx] = x - size_diff
            end
          when :insert
            if normalized_iseq_ref(x) >= i and (n < i or n > k)
              @iseq[n.succ + arg_idx] = x + size_diff
            end
          end
        end
      end
    end
  end

  def duplicate_iseq(range)
    @iseq += @iseq[range]
  end

  def offset_iseq_refs(range)
    first_index = range.first

    for i in range
      if arg_idx = at_ins_with_iseq_ref?(i)
        k = @iseq[i.succ + arg_idx]
        unless @immutable_iseq_refs.include? k
          @iseq[i.succ + arg_idx] = k + first_index + ISEQ_REF_OFFSET
        end
      end
    end
  end

  # use after offset_iseq_refs + delete/insert
  #
  def normalize_iseq_refs

    @iseq.each_index do |i|

      if arg_idx = at_ins_with_iseq_ref?(i)
        k = @iseq[i.succ + arg_idx]
        @iseq[i.succ + arg_idx] = normalized_iseq_ref(k)
      end
    end
  end

  def normalized_iseq_ref(num)
    if num - ISEQ_REF_OFFSET >= 0
      num - ISEQ_REF_OFFSET
    else
      num
    end
  end

  def obsolete_recalculate_exceptions(action, i, size_diff)
    return if size_diff == 0
    k = i + (size_diff - 1)

    n = 0
    while n < @exceptions.length
      first, last, other = @exceptions[n]

      raise "error: recalculate_exceptions: garbage '#{@cm.name}'" unless
        other > last and last >= first

      case action
      when :delete

        if first >= i and last <= k
          @exceptions.delete_at(n)
          n -= 1
        elsif first >= i and first <= k
          @exceptions[n] = [i, last - size_diff, other - size_diff]
        elsif first < i and last >= i and last <= k
          if other > k
            @exceptions[n] = [first, i - 1, other - size_diff]
          else
            @exceptions[n] = [first, i - 1, i]
          end
        elsif first < i and last > k
          @exceptions[n] = [first, last - size_diff, other - size_diff]
        elsif first > k and last > k
          @exceptions[n] = [first - size_diff, last - size_diff, other - size_diff]
        elsif other >= i and other <= k
          @exceptions[n] = [first, last, i]
        elsif other > k
          @exceptions[n] = [first, last, other - size_diff]
        end
      when :insert

        new_first = (first >= i ? first + size_diff : first)
        new_last  = (last >= i ? last + size_diff : last)
        new_other = (other >= i ? other + size_diff : other)

        @exceptions[n] = [new_first, new_last, new_other]
      when :swap

        x = self.next(i)
        old_x = i + (k - x).succ

        new_first = if first > i and first <= k
                      if first < old_x
                        x - 1
                      elsif first > old_x
                        k
                      else
                        x
                      end
                    else
                      first
                    end

        new_last = if last > i and last <= k
                     if last < old_x
                       x - 1
                     elsif last > old_x
                       k
                     else
                       x
                     end
                   else
                     last
                   end

        new_other = if other > i and other <= k
                      if other < old_x
                        x - 1
                      elsif other > old_x
                        k
                      else
                        x
                      end
                    else
                      other
                    end

        @exceptions[n] = [new_first, new_last, new_other]
      end

      n += 1
    end
  end

  def obsolete_duplicate_exceptions(range)
    for i in range
      first, last, other = @exceptions[i]
      @exceptions << [first, last, other]
    end
  end

  def obsolete_offset_exceptions(range, offset)
    for i in range
      first, last, other = @exceptions[i]
      @exceptions[i] = [first + offset, last + offset, other + offset]
    end
  end

  def recalculate_lines(action, i, size_diff)
    return if size_diff == 0
    k = i + (size_diff - 1)
    len = @lines.length

    n = 0
    while n < len
      x = @lines[n]

      case action
      when :delete
        if x > k
          @lines[n] = x - size_diff
        elsif x > i and x <= k
          @lines[n] = i
        end
      when :insert
        if x >= i
          @lines[n] = x + size_diff
        end
      when :swap
        if x > i and x <= k
          @lines[n] = self.next(i)
        end
      end

      n += 2
    end

    sweep_lines if action == :delete
  end

  def sweep_lines

    i = 0
    while i < @lines.length and @lines.length > 3
      k = i + 2
      if @lines[i] == @lines[k]
        2.times { @lines.delete_at(i) }
      else
        i += 2
      end
    end

    if @iseq.length == 0
      @lines = []
    elsif @lines.length > 0 and @lines[-1] >= @iseq.length
      @lines[-1] = @iseq.length - 1
    end
  end

  def duplicate_lines(range)
    @lines += @lines[range]
  end

  # assumes first and last in range point to refs to iseq
  #
  def offset_lines(range, offset)
    i = range.first
    k = range.last

    while i <= k
      @lines[i] += offset
      i += 2
    end
  end

  def delete_literal(i, num_del = 1)
    oldsize = @literals.length

    if i < 0
      i += oldsize
    end

    num_del.times { @literals.delete_at(i) }

    newsize = @literals.length
    size_diff = oldsize - newsize

    recalculate_literals(:delete, i, size_diff)
  end

  def recalculate_literals(action, i, size_diff)

    if size_diff == 0 or action != :delete
      return
    end

    k = i + (size_diff - 1)

    @iseq.each_index do |n|

      if arg_idx = at_ins_with_literal?(n)
        x = @iseq[n.succ + arg_idx]
        if x > k
          @iseq[n.succ + arg_idx] = x - size_diff
        end
      elsif at_ins_with_literals?(n)
        x0 = @iseq[n.succ]
        x1 = @iseq[n.succ.succ]
        if x0 > k
          @iseq[n.succ] = x0 - size_diff
        end
        if x1 > k
          @iseq[n.succ.succ] = x1 - size_diff
        end
      end
    end
  end

  def offset_literals(range, offset)
    for i in range
      if arg_idx = at_ins_with_literal?(i)
        @iseq[i.succ + arg_idx] += offset
      elsif at_ins_with_literals?(i)
        @iseq[i.succ] += offset
        @iseq[i.succ.succ] += offset
      end
    end
  end

  def offset_locals(range, offset = @cm.local_count)
    high = -1

    for i in range
      if arg_idx = at_ins_with_local?(i)
        k = (@iseq[i.succ + arg_idx] += offset)
        high = k if k > high
      end
    end

    if high >= @cm.local_count
      @cm.local_count = high.succ
    end
  end

  def self.wrap(iseq)
    layered_iseq = []
    arr = []

    iseq.each do |obj|

      case obj
      when Symbol
        if arr.empty?
          arr << obj
        else
          layered_iseq << arr
          arr = [obj]
        end
      when Integer
        arr << obj
      else
        raise "error: InstructionChanges.wrap: bad object type '#{obj.class}'"
      end
    end

    if arr.empty?
      layered_iseq
    else
      layered_iseq << arr
    end
  end

  def self.to_tup(ary)
    tup = Rubinius::Tuple.new(ary.size)
    ary.each_index do |i|
      tup[i] = ary[i]
    end
    tup
  end

  def test

    encoder = Rubinius::InstructionSequence::Encoder.new
    cm = Rubinius::CompiledMethod.new
    cm.iseq = encoder.encode_stream([[:passed_arg, 10], [:push_true]])

    ic = InstructionChanges.new(cm)
    ic.never_shrink = false

    ic.iseq = [:foo, 10, :hi]
    ic.literals = []
    #ic.exceptions = []
    ic.lines = []

    raise "fail 0" unless ic.next(0) == 2
    raise "fail 1" unless ic.previous(2) == 0

    ic.delete(0)
    raise "fail 2" unless ic.iseq == [:hi]

    ic.insert(0, [:goto, 25])
    raise "fail 3" unless ic.iseq == [:goto, 25, :hi]

    ic.replace(1, 2)
    raise "fail 4" unless ic.iseq == [:goto, 2, :hi]

    ic.insert(-1, [:hello, 10, 20, :what, :goto_if_true, 7, :hey, :goto, 0])
    raise "fail 5" unless
      ic.iseq == [:goto, 2, :hi, :hello, 10, 20, :what, :goto_if_true, 7, :hey, :goto, 0]

    ic.delete(3)
    raise "fail 6" unless
      ic.iseq == [:goto, 2, :hi, :what, :goto_if_true, 4, :hey, :goto, 0]

    ic.delete(0)
    raise "fail 7" unless ic.iseq == [:hi, :what, :goto_if_true, 2, :hey, :goto, 0]

    ic.replace(6, 4)
    raise "fail 8" unless ic.iseq == [:hi, :what, :goto_if_true, 2, :hey, :goto, 4]

    ic.delete(2)
    raise "fail 9" unless ic.iseq == [:hi, :what, :hey, :goto, 2]

    ic.delete(0)
    raise "fail 10" unless ic.iseq == [:what, :hey, :goto, 1]

    ic.insert(0, [:goto, 2])
    raise "fail 11" unless ic.iseq == [:goto, 2, :what, :hey, :goto, 3]

    ic.insert(2, [:foo])
    raise "fail 12" unless ic.iseq == [:goto, 3, :foo, :what, :hey, :goto, 4]

    ic.delete(3)
    raise "fail 13" unless ic.iseq == [:goto, 3, :foo, :hey, :goto, 3]

    ic.delete(8)
    raise "fail 14" unless ic.iseq == [:goto, 3, :foo, :hey, :goto, 3]

    ic.insert(8, [:oh])
    raise "fail 15" unless ic.iseq == [:goto, 3, :foo, :hey, :goto, 3, nil, nil, :oh]

    ic.iseq = [:goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 4, :where, :goto, 8]

    ic.insert(-1, ic.iseq)
    raise "fail 16" unless
      ic.iseq == [:goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 4, :where, :goto, 8,
                  :goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 4, :where, :goto, 8]

    ic.replace(18, 11)
    raise "fail 17" unless
      ic.iseq == [:goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 4, :where, :goto, 8,
                  :goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 11, :where, :goto, 8]

    ic.immutable_iseq_refs = [11]
    ic.offset_iseq_refs(11..21)
    ic.normalize_iseq_refs
    raise "fail 18" unless
      ic.iseq == [:goto, 2, :foo, :hi, :goto, 3, :goto_if_false, 4, :where, :goto, 8,
                  :goto, 13, :foo, :hi, :goto, 14, :goto_if_false, 11, :where, :goto, 19]

    ic.iseq = [:hi, 1, :why, 10]
    raise "fail 19" unless ic.previous(0).nil?
    raise "fail 20" unless ic.next(2).nil?

    ic.immutable_iseq_refs = [6]
    ic.iseq = [:goto, 3, :hello, :hi, :goto_if_true, 6, :foo, :when, :dinosaur, 3, 4]

    ic.delete(2)
    raise "fail 21" unless
      ic.iseq == [:goto, 2, :hi, :goto_if_true, 6, :foo, :when, :dinosaur, 3, 3]

    ic.immutable_iseq_refs = []
    ic.iseq = [:here, 5, :where, 10]
    ic.replace(1, 8, :when)
    raise "fail 22" unless ic.iseq == [:here, 8, :when, 10]

    ic.delete(0, 3)
    raise "fail 23" unless ic.iseq == [10]

    ic.iseq = [:hi, 1, :why, 10, :foo]
    raise "fail 24" unless
      InstructionChanges.wrap(ic.iseq) == [[:hi, 1], [:why, 10], [:foo]]

    ic.iseq = [:goto, 2, :here, :foo, 10, :goto, 7, :what]
    ic.offset_iseq_refs(0..7)
    ic.delete(3)
    ic.insert(3, [:foo])
    ic.insert(0, [:huh])
    ic.normalize_iseq_refs
    raise "fail 24.1" unless ic.iseq == [:huh, :goto, 3, :here, :foo, :goto, 7, :what]

    #ic.iseq = [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l,
    #           :m, :n, :o, :p, :q, :r, :s, :t, :u, :v, :w, :x, :y, :z]
    #ic.exceptions = [[0, 2, 24], [3, 7, 8], [9, 19, 22], [20, 20, 21]]

    #ic.delete(0, 3)
    #raise "fail 25" unless ic.exceptions == [[0, 4, 5], [6, 16, 19], [17, 17, 18]]

    #ic.delete(6, 2)
    #raise "fail 26" unless ic.exceptions == [[0, 4, 5], [6, 14, 17], [15, 15, 16]]

    #ic.delete(14, 4)
    #raise "fail 27" unless ic.exceptions == [[0, 4, 5], [6, 13, 14]]

    #ic.delete(13)
    #raise "fail 28" unless ic.exceptions == [[0, 4, 5], [6, 12, 13]]

    #ic.delete(8, 2)
    #raise "fail 29" unless ic.exceptions == [[0, 4, 5], [6, 10, 11]]

    #ic.delete(3)
    #raise "fail 30" unless ic.exceptions == [[0, 3, 4], [5, 9, 10]]

    #ic.delete(4)
    #raise "fail 31" unless ic.exceptions == [[0, 3, 4], [4, 8, 9]]

    #ic.insert(4, [:a, :b])
    #raise "fail 32" unless ic.exceptions == [[0, 3, 6], [6, 10, 11]]

    #ic.insert(12, [:foo])
    #raise "fail 33" unless ic.exceptions == [[0, 3, 6], [6, 10, 11]]
    #raise "fail 34" unless
    #  ic.iseq == [:d, :e, :f, :h, :a, :b, :l, :m, :p, :q, :r, :x, :foo, :y, :z]

    #ic.duplicate_exceptions(0..0)
    #raise "fail 35" unless ic.exceptions == [[0, 3, 6], [6, 10, 11], [0, 3, 6]]

    #ic.offset_exceptions(1..2, 3)
    #raise "fail 36" unless ic.exceptions == [[0, 3, 6], [9, 13, 14], [3, 6, 9]]

    ic.iseq = [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l,
               :m, :n, :o, :p, :q, :r, :s, :t, :u, :v, :w, :x, :y, :z]
    ic.lines = [0, 24, 2, 8, 7, 22, 19, 21, 20]

    ic.delete(0, 3)
    raise "fail 37" unless ic.lines == [0, 8, 4, 22, 16, 21, 17]

    ic.delete(6, 2)
    raise "fail 38" unless ic.lines == [0, 8, 4, 22, 14, 21, 15]

    ic.delete(14, 4)
    raise "fail 39" unless ic.lines == [0, 8, 4, 22, 14]

    ic.delete(13)
    raise "fail 40" unless ic.lines == [0, 8, 4, 22, 13]

    ic.delete(8, 2)
    raise "fail 41" unless ic.lines == [0, 8, 4, 22, 11]

    ic.delete(3)
    raise "fail 42" unless ic.lines == [0, 8, 3, 22, 10]

    ic.delete(4)
    raise "fail 43" unless ic.lines == [0, 8, 3, 22, 9]

    ic.insert(4, [:a, :b])
    raise "fail 44" unless ic.lines == [0, 8, 3, 22, 11]

    ic.insert(12, [:foo])
    raise "fail 45" unless ic.lines == [0, 8, 3, 22, 11]
    raise "fail 46" unless
      ic.iseq == [:d, :e, :f, :h, :a, :b, :l, :m, :p, :q, :r, :x, :foo, :y, :z]

    ic.delete(9, 10)
    raise "fail 46.1" unless ic.lines == [0, 8, 3, 22, 8]

    ic.iseq = [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m, :n, :o, :p]
    ic.lines = [0, 3, 1, 6, 2, 4, 3, 9, 4]

    ic.delete(0, 4)
    raise "fail 46.2" unless ic.lines == [0, 9, 0]

    ic.lines = [0, 3, 1, 6, 2, 4, 3, 9, 4]

    ic.delete(0, 3)
    raise "fail 46.3" unless ic.lines == [0, 9, 1]

    ic.lines = [0, 3, 1, 6, 2, 4, 3, 9, 4]

    ic.delete(0, 2)
    raise "fail 46.4" unless ic.lines == [0, 4, 1, 9, 2]

    ic.duplicate_lines(0..2)
    raise "fail 47" unless ic.lines == [0, 4, 1, 9, 2, 0, 4, 1]

    ic.offset_lines(2..4, 3)
    raise "fail 48" unless ic.lines == [0, 4, 4, 9, 5, 0, 4, 1]

    ic.iseq = [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m]
    #ic.exceptions = [[8, 9, 10]]
    ic.lines = [9, 50, 10]

    ic.duplicate_iseq(4..5)
    raise "fail 49" unless
      ic.iseq == [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m, :e, :f]
    #raise "fail 50" unless ic.exceptions == [[8, 9, 10]]
    raise "fail 51" unless ic.lines == [9, 50, 10]

    ic.iseq = [:push_literal, 5, :goto, 4, :foo, :dummy, 99, 6, :push_const_fast, 7, 3]
    ic.literals = [:blah, :hello, :hi, :oh, :no, :hey, :howdy, :foo]

    ic.delete_literal(1, 2)
    raise "fail 58" unless
      ic.iseq == [:push_literal, 3, :goto, 4, :foo, :dummy, 99, 4, :push_const_fast, 5, 1]
    raise "fail 59" unless ic.literals == [:blah, :oh, :no, :hey, :howdy, :foo]

    ic.delete_literal(-1)
    raise "fail 60" unless
      ic.iseq == [:push_literal, 3, :goto, 4, :foo, :dummy, 99, 4, :push_const_fast, 5, 1]
    raise "fail 61" unless ic.literals == [:blah, :oh, :no, :hey, :howdy]

    ic.delete_literal(2)
    raise "fail 62" unless
      ic.iseq == [:push_literal, 2, :goto, 4, :foo, :dummy, 99, 3, :push_const_fast, 4, 1]
    raise "fail 63" unless ic.literals == [:blah, :oh, :hey, :howdy]

    ic.delete_literal(2)
    raise "fail 64" unless
      ic.iseq == [:push_literal, 2, :goto, 4, :foo, :dummy, 99, 2, :push_const_fast, 3, 1]
    raise "fail 65" unless ic.literals == [:blah, :oh, :howdy]

    ic.offset_literals(0..0, 17)
    raise "fail 66" unless
      ic.iseq == [:push_literal, 19, :goto, 4, :foo, :dummy, 99, 2, :push_const_fast, 3, 1]
    raise "fail 67" unless ic.literals == [:blah, :oh, :howdy]

    ic.offset_literals(8..8, 5)
    raise "fail 67.1" unless
      ic.iseq == [:push_literal, 19, :goto, 4, :foo, :dummy, 99, 2, :push_const_fast, 8, 6]
    raise "fail 67.2" unless ic.literals == [:blah, :oh, :howdy]

    ic.cm.local_count = 3
    ic.iseq = [:push_local_depth, 9, 7, :goto, 5, :set_local, 3]

    ic.offset_locals(0..1)
    raise "fail 68.0" unless ic.iseq == [:push_local_depth, 9, 10, :goto, 5, :set_local, 3]
    raise "fail 68.1" unless ic.cm.local_count == 11

    ic.offset_locals(2..6, 1)
    raise "fail 68.2" unless ic.iseq == [:push_local_depth, 9, 10, :goto, 5, :set_local, 4]
    raise "fail 68.3" unless ic.cm.local_count == 11

    ic.offset_locals(0..6, 13)
    raise "fail 68.4" unless ic.iseq == [:push_local_depth, 9, 23, :goto, 5, :set_local, 17]
    raise "fail 68.5" unless ic.cm.local_count == 24

    ic.iseq = [:set_local_depth, 2, 3, :foo, :set_literal, 3]
    raise "fail 70" unless ic.at_ins_with_literal?(4) == 0
    raise "fail 71" unless ic.at_ins_with_local?(0) == 1
    raise "fail 72" unless ic.at_ins_with_literal?(3) == nil
    raise "fail 73" unless ic.at_ins_with_local?(3) == nil

    ic.iseq = [:foo, :hi, 4, 3, :no, :goto, 4, :goto_if_true, 7, :hello, :goto, 4]
    #ic.exceptions = [[0, 3, 5], [4, 4, 9], [1, 2, 4], [0, 9, 10], [5, 6, 7], [1, 4, 5]]
    ic.lines = [0, 5, 4, 4, 9, 4, 1, 4, 5, 0, 10, 9, 5, 7, 7, 1, 5, 4, 10]

    ic.swap(5)
    raise "fail 74.0" unless
      ic.iseq == [:foo, :hi, 4, 3, :no, :goto_if_true, 7, :goto, 4, :hello, :goto, 4]
    #raise "fail 74.1" unless
    #  ic.exceptions == [[0, 3, 5], [4, 4, 9], [1, 2, 4], [0, 9, 10], [5, 6, 7], [1, 4, 5]]
    raise "fail 74.2" unless
      ic.lines == [0, 5, 4, 4, 9, 4, 1, 4, 5, 0, 10, 9, 5, 7, 7, 1, 5, 4, 10]

    ic.swap(1)
    raise "fail 75.0" unless
      ic.iseq == [:foo, :no, :hi, 4, 3, :goto_if_true, 7, :goto, 2, :hello, :goto, 2]
    #raise "fail 75.1" unless
    #  ic.exceptions == [[0, 1, 5], [2, 2, 9], [1, 1, 2], [0, 9, 10], [5, 6, 7], [1, 2, 5]]
    raise "fail 75.2" unless
      ic.lines == [0, 5, 2, 4, 9, 4, 1, 4, 5, 0, 10, 9, 5, 7, 7, 1, 5, 4, 10]

    ic.swap(1)
    raise "fail 76.0" unless
      ic.iseq == [:foo, :hi, 4, 3, :no, :goto_if_true, 7, :goto, 4, :hello, :goto, 4]
    #raise "fail 76.1" unless
    #  ic.exceptions == [[0, 1, 5], [4, 4, 9], [1, 1, 4], [0, 9, 10], [5, 6, 7], [1, 4, 5]]
    raise "fail 76.2" unless
      ic.lines == [0, 5, 4, 4, 9, 4, 1, 4, 5, 0, 10, 9, 5, 7, 7, 1, 5, 4, 10]

    ic.iseq = [:foo, 15, :hi, 23, 57, :what]
    #ic.exceptions = [[1, 2, 4]]
    ic.lines = [2, 4, 5]

    ic.swap(0)
    raise "fail 76.3" unless ic.iseq == [:hi, 23, 57, :foo, 15, :what]
    #raise "fail 76.4" unless ic.exceptions == [[2, 3, 4]]
    raise "fail 76.5" unless ic.lines == [3, 4, 5]

    # why goto denormalization-normalization is needed.
    # in this example the first goto's argument should be frozen since it's equal
    # to a number in @immutable_iseq_refs at the time @immutable_iseq_refs is set.
    # other goto arguments should be modifiable even if they equal a number in
    # @immutable_iseq_refs after an offset_iseq_refs modification.

    ic.immutable_iseq_refs = [6]
    ic.iseq = [:goto, 6, :foo, :hello, :goto, 2, :hi, :what]

    ic.offset_iseq_refs(4..7)
    raise "fail 77" unless
      ic.iseq == [:goto, 6, :foo, :hello, :goto, ISEQ_REF_OFFSET + 6, :hi, :what]

    ic.delete(3)
    raise "fail 78" unless
      ic.iseq == [:goto, 6, :foo, :goto, ISEQ_REF_OFFSET + 5, :hi, :what]

    ic.normalize_iseq_refs
    raise "fail 79" unless ic.iseq == [:goto, 6, :foo, :goto, 5, :hi, :what]

    #ic.iseq = [:hello, 3, :foo, :hi, 2, :what]
    #ic.exceptions = [[0, 1, 5]]

    #ic.delete(2)
    #raise "fail 80" unless ic.iseq == [:hello, 3, :hi, 2, :what]
    #raise "fail 81" unless ic.exceptions == [[0, 1, 4]]

    ic.iseq = [:goto, 2, :hi]
    #ic.exceptions = [[0, 1, 2]]
    ic.lines = [0, 5, 2]

    ic.insert(0, [])
    raise "fail 82.0" unless ic.iseq == [:goto, 2, :hi]
    #raise "fail 82.1" unless ic.exceptions == [[0, 1, 2]]
    raise "fail 82.2" unless ic.lines == [0, 5, 2]

    ic.iseq = [:push_true]

    ic.finalize
    raise "fail 83.0" unless ic.cm.iseq.instance_of? Rubinius::InstructionSequence
    raise "fail 83.1" unless ic.cm.literals.instance_of? Rubinius::Tuple
    raise "fail 83.2" unless ic.cm.local_names.instance_of? Rubinius::Tuple
    #raise "fail 83.3" unless ic.cm.exceptions.instance_of? Rubinius::Tuple
    raise "fail 83.4" unless ic.cm.lines.instance_of? Rubinius::Tuple
  end
end

