class GithubSyncJob < BackgroundJob
  MAX_FETCHED_COMMITS = 10
  queue_as :default

  self.timeout = 60

  extend Resque::Plugins::Workers::Lock

  def self.lock_workers(params)
    "github-sync-#{params[:stack_id]}"
  end

  def perform(params)
    @stack = Stack.find(params[:stack_id])

    new_commits, shared_parent = fetch_missing_commits { @stack.github_commits }

    @stack.transaction do
      shared_parent.try(:detach_children!)
      new_commits.each do |gh_commit|
        @stack.commits.create_from_github!(gh_commit)
      end
    end
  end

  def fetch_missing_commits(&block)
    commits = []
    iterator = FirstParentCommitsIterator.new(&block)
    iterator.each_with_index do |commit, index|
      break if index >= MAX_FETCHED_COMMITS

      if shared_parent = lookup_commit(commit.sha)
        return commits, shared_parent
      end
      commits.unshift(commit)
    end
    return commits, nil
  end

  protected

  def lookup_commit(sha)
    @stack.commits.find_by_sha(sha)
  end
end
