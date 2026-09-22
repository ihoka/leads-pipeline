module Sources
  class Adapter
    def self.key
      raise NotImplementedError, "#{name} must define .key"
    end

    def self.manifest
      raise NotImplementedError, "#{name} must define .manifest"
    end

    def search(params)
      raise NotImplementedError, "#{self.class.name} must define #search"
    end
  end
end
