# frozen_string_literal: true

RSpec.describe RSpec::Signal::Rerun do
  describe ".quote" do
    it "leaves an ordinary spec location alone" do
      expect(described_class.quote("spec/models/user_spec.rb:12")).to eq("spec/models/user_spec.rb:12")
    end

    # `[` and `]` are glob metacharacters. bash passes an unmatched glob
    # through unchanged, but zsh fails the whole command, so an unquoted
    # example id is a command that works for some readers and not others.
    it "quotes an example id" do
      expect(described_class.quote("./spec/models/user_spec.rb[1:3]"))
        .to eq("'./spec/models/user_spec.rb[1:3]'")
    end

    it "quotes a path containing a space" do
      expect(described_class.quote("spec/my specs/user_spec.rb:1")).to eq("'spec/my specs/user_spec.rb:1'")
    end

    it "escapes an embedded single quote" do
      expect(described_class.quote("spec/o'brien_spec.rb[1:1]")).to eq(%q('spec/o'\''brien_spec.rb[1:1]'))
    end
  end

  describe ".command" do
    it "builds a copy-pasteable command" do
      expect(described_class.command(["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[2:1]"]))
        .to eq("bundle exec rspec './spec/a_spec.rb[1:1]' './spec/b_spec.rb[2:1]'")
    end

    it "accepts a different runner prefix" do
      expect(described_class.command(["spec/a_spec.rb:1"], prefix: "bin/rspec"))
        .to eq("bin/rspec spec/a_spec.rb:1")
    end
  end
end
