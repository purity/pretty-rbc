
module TestHeap

  def self.fad(n)
                      # __stack__ = []
    if n <= 0
      0
    else
                      # __stack__ << n
      n + fad(n - 1)  # __stack__ << 0
    end
                      # if __stack__.empty?
                      #   <return>
                      # else
                      #   __iseq_id__ = __stack__.pop
                      #   n = __stack__.pop
                      #   if __iseq_id__ == 0
                      #     <resume in original>
                      #   elsif __iseq_id__ == 1
                      #     <resume in first copy>
  end

  def self.fib(n, useful = :no)
    if n <= 1
      begin
        raise n.to_s
      rescue Exception => e
        e.to_s.to_i
      end
    else
      begin
        x = n - 2
        y = n - 1
        z = fib(x, :yes) + fib(y)
        raise z.to_s
      rescue Exception => e
        e.to_s.to_i
      end
    end
  end

  def self.make_btree(ary, numl = 0, numr = (ary.length - 1))
    if numl > numr
      nil
    else
      i = ((numr - numl) / 2) + numl
      [make_btree(ary, numl, i - 1), ary[i], make_btree(ary, i.succ, numr)]
    end
  end

  def self.make_array(bt)
    if bt.nil?
      []
    else
      make_array(bt[0]) + [bt[1]] + make_array(bt[2])
    end
  end
end

num = 200_000
ary = (0..99999).to_a

puts TestHeap.fad(num)

puts TestHeap.make_array(TestHeap.make_btree(ary)) == ary

puts TestHeap.fib(20)

