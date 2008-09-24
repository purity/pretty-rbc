
module TestFunc

  def self.to_two(n)
    if n <= 2
      2
    else
      to_two(n - 1)
    end
  end

  def self.fib(n, a = 0, b = 1)
    if n <= 0
      a
    else
      fib(n - 1, b, a + b)
    end
  end

  def self.foldl(f, acc, arr, i = 0)
    if i >= arr.size
      acc
    else
      foldl(f, f.call(acc, arr[i]), arr, i.succ)
    end
  end

  def self.yucky(a, b = 10)
    if b <= 0
      begin
        raise "bye"
      rescue Exception
        777
      end
    elsif a <= 0
      begin
        yucky(a, b - 1)
      rescue Exception
        nil
      end
    else
      begin
        yucky(a - 1)
      rescue Exception
        false
      end
    end
  end

  def self.gross(action = nil, num = 0)
    case action
    when :add
      begin
        gross(:return, 5 + 5)
      rescue Exception
        nil
      end
    when :return
      begin
        raise "bye"
      rescue Exception
        num
      end
    else
      begin
        raise "to tail"
      rescue Exception
        # not a genuine tail call because of 
        # clear_exception after send_stack
        gross(:add)
      end
    end
  end

  def self.broken_0(func = nil)
    if func
      c = 111
      func.call
    else
      b = 5
      c = 25
      func = lambda do b + c end
      broken_0(func)
    end
  end

  def self.broken_1(n = 0)
    if n >= 10
      raise "bad"
    else
      begin
        broken_1(n.succ)
      rescue Exception
        :good
      end
    end
  end

  # iterative fib
  #
  def self.fub(n)
    a = 0
    b = 1
    while n > 0
      tmp = a + b
      a = b
      b = tmp
      n -= 1
    end
    a
  end
end



num = 6_000_000

puts TestFunc.fib(num / 1_000) == TestFunc.fub(num / 1_000)

puts TestFunc.to_two(num)
puts TestFunc.yucky(num)
puts TestFunc.gross

sum = lambda do |acc, num| acc + num end
numbers = Array.new(1_000_000, 5)

puts TestFunc.foldl(sum, 0, numbers) == numbers.inject(0) { |acc, num| acc + num }

reverse = lambda do |acc, obj| acc.unshift(obj) end
numbers = (0..9_999).to_a

puts TestFunc.foldl(reverse, [], numbers) == numbers.inject([]) { |acc, obj| acc.unshift(obj) }

