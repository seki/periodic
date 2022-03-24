class Bucket
  def initialize
    @dir = "data/"
  end

  def put_object(key, body)
    File.write(@dir + key, body) 
  end

  def get_object(key)
    File.read(@dir + key)
  end
end
