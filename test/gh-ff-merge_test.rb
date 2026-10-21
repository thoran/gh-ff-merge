# test/gh-ff-merge_test.rb

# 20261021
# 0.2.0

# Each test runs gh-ff-merge as a subprocess in a clone of a bare repository
# made for the purpose, standing in for origin, with a fake gh first on the
# path, and asserts upon where the branches on origin and in the clone end up.
# The fake gh answers `gh pr view` from pull_request.json, and with --jq,
# from states, a state a line, taken in turn and the last repeating; where
# pull_request.json is absent it fails, as gh does with no pull request.

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

BIN = File.expand_path('../gh-ff-merge', __dir__)
URL = 'https://github.com/thoran/example/pull/1'

FAKE_GH = <<~'RUBY'
  #!/usr/bin/env ruby
  directory = File.dirname(__FILE__)
  pull_request = File.join(directory, 'pull_request.json')
  exit 1 unless File.exist?(pull_request)
  if ARGV.include?('--jq')
    states = File.readlines(File.join(directory, 'states'), chomp: true)
    File.write(File.join(directory, 'states'), states.drop(1).join("\n")) if states.length > 1
    puts states.first
  else
    puts File.read(pull_request)
  end
RUBY

ENV['GIT_CONFIG_COUNT'] = '2'
ENV['GIT_CONFIG_KEY_0'] = 'commit.gpgsign'
ENV['GIT_CONFIG_VALUE_0'] = 'false'
ENV['GIT_CONFIG_KEY_1'] = 'advice.detachedHead'
ENV['GIT_CONFIG_VALUE_1'] = 'false'

def git(*arguments)
  system('git', *arguments, out: File::NULL, err: File::NULL) || raise("git #{arguments.join(' ')} failed")
end

def commit_on(branch, message)
  git('checkout', branch)
  git('commit', '--allow-empty', '-m', message)
end

def branch_from(start, branch, *messages)
  git('checkout', '-b', branch, start)
  messages.each{|message| git('commit', '--allow-empty', '-m', message)}
end

def sha(ref)
  `git rev-parse --verify --quiet #{ref}`.strip
end

def origin_sha(branch)
  `git ls-remote origin refs/heads/#{branch}`.split.first
end

def fake_gh_directory
  @fake_gh_directory
end

def pull_request(state: 'OPEN', base: 'master', head: sha('HEAD'), states: ['MERGED'])
  File.write(File.join(fake_gh_directory, 'pull_request.json'), JSON.generate(state: state, baseRefName: base, headRefOid: head, url: URL))
  File.write(File.join(fake_gh_directory, 'states'), states.join("\n"))
end

def in_clone
  Dir.mktmpdir do |directory|
    Dir.chdir(directory) do
      @fake_gh_directory = File.join(directory, 'bin')
      Dir.mkdir(fake_gh_directory)
      File.write(File.join(fake_gh_directory, 'gh'), FAKE_GH)
      File.chmod(0755, File.join(fake_gh_directory, 'gh'))
      git('init', '--bare', '-b', 'master', 'origin.git')
      git('clone', 'origin.git', 'seed')
      Dir.chdir('seed'){git('commit', '--allow-empty', '-m', 'first'); git('push', 'origin', 'master')}
      git('clone', 'origin.git', 'clone')
      Dir.chdir('clone'){yield}
    end
  end
end

def ff_merge(*arguments)
  path = "#{fake_gh_directory}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
  stdout, stderr, status = Open3.capture3({'PATH' => path}, BIN, *arguments)
  [status.exitstatus, stdout + stderr]
end

describe 'gh-ff-merge' do
  it "fast-forwards the pull request's base branch to the branch" do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request
      status, output = ff_merge
      _(status).must_equal 0
      _(output).must_include "Merged #{URL}"
      _(origin_sha('master')).must_equal sha('fix')
      _(sha('HEAD')).must_equal sha('fix')
      _(origin_sha('fix')).must_equal sha('fix')
    end
  end

  it "fast-forwards the pull request's base branch where it isn't the default branch" do
    in_clone do
      branch_from('master', 'develop', 'on develop')
      git('push', 'origin', 'develop')
      branch_from('develop', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request(base: 'develop')
      master = origin_sha('master')
      status, _output = ff_merge
      _(status).must_equal 0
      _(origin_sha('develop')).must_equal sha('fix')
      _(origin_sha('master')).must_equal master
    end
  end

  it 'stops where there is no pull request' do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      master = origin_sha('master')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include 'fix has no open pull request.'
      _(origin_sha('master')).must_equal master
    end
  end

  it "stops where the pull request isn't open" do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request(state: 'CLOSED')
      master = origin_sha('master')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include 'fix has no open pull request.'
      _(origin_sha('master')).must_equal master
    end
  end

  it "stops where the branch isn't the pull request's head" do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request
      git('commit', '--allow-empty', '-m', 'not pushed')
      master = origin_sha('master')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include "fix is not the pull request's head."
      _(output).must_include 'run `gh ff-merge` again'
      _(origin_sha('master')).must_equal master
    end
  end

  it 'stops where the base branch has moved on' do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request
      branch_from('master', 'other', 'elsewhere')
      git('push', 'origin', 'other:master')
      git('checkout', 'fix')
      master = origin_sha('master')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include 'master has moved on since fix was cut.'
      _(origin_sha('master')).must_equal master
    end
  end

  it 'stops where the local base branch has commits of its own' do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request
      commit_on('master', 'local only')
      git('checkout', 'fix')
      master = origin_sha('master')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include 'master has commits of its own'
      _(origin_sha('master')).must_equal master
    end
  end

  it 'stops on a detached HEAD' do
    in_clone do
      branch_from('master', 'fix', 'the fix')
      git('push', 'origin', 'fix')
      pull_request
      git('checkout', '--detach')
      status, output = ff_merge
      _(status).must_equal 1
      _(output).must_include 'Not on a branch.'
    end
  end

  it 'stops given more than one base branch' do
    in_clone do
      status, output = ff_merge('master', 'develop')
      _(status).must_equal 1
      _(output).must_include 'Usage: gh ff-merge'
    end
  end

  describe 'with a base branch named' do
    it "fast-forwards it where it is the pull request's" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', 'origin', 'fix')
        pull_request
        status, _output = ff_merge('master')
        _(status).must_equal 0
        _(origin_sha('master')).must_equal sha('fix')
      end
    end

    it "stops where it isn't the pull request's" do
      in_clone do
        branch_from('master', 'develop', 'on develop')
        git('push', 'origin', 'develop')
        branch_from('develop', 'fix', 'the fix')
        git('push', 'origin', 'fix')
        pull_request
        master = origin_sha('master')
        develop = origin_sha('develop')
        status, output = ff_merge('develop')
        _(status).must_equal 1
        _(output).must_include "develop isn't the base branch of #{URL}, which is master."
        _(origin_sha('master')).must_equal master
        _(origin_sha('develop')).must_equal develop
      end
    end
  end

  describe '-d' do
    it 'deletes the branch on origin and locally once GitHub reports it merged' do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', 'origin', 'fix')
        pull_request(states: ['OPEN', 'MERGED'])
        fix = sha('fix')
        status, _output = ff_merge('-d')
        _(status).must_equal 0
        _(origin_sha('master')).must_equal fix
        _(origin_sha('fix')).must_be_nil
        _(sha('refs/heads/fix')).must_be_empty
      end
    end

    it 'deletes only the local branch where the branch on origin is already gone' do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', 'origin', 'fix')
        pull_request
        git('push', 'origin', '--delete', 'fix')
        status, output = ff_merge('-d')
        _(status).must_equal 0
        _(output).wont_include 'deleted'
        _(origin_sha('master')).must_equal sha('master')
        _(sha('refs/heads/fix')).must_be_empty
      end
    end

    it "keeps the branch where GitHub doesn't report it merged" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', 'origin', 'fix')
        pull_request(states: ['OPEN'])
        fix = sha('fix')
        status, output = ff_merge('-d')
        _(status).must_equal 1
        _(output).must_include "GitHub hasn't yet marked #{URL} merged, so fix is kept."
        _(origin_sha('master')).must_equal fix
        _(origin_sha('fix')).must_equal fix
        _(sha('refs/heads/fix')).must_equal fix
      end
    end
  end
end
