require "spec_helper"

describe NotesHelper do
  include RepoHelpers

  let(:owner) { create(:owner) }
  let(:group) { create(:group) }
  let(:project) { create(:project, namespace: group) }
  let(:master) { create(:user) }
  let(:reporter) { create(:user) }
  let(:guest) { create(:user) }

  let(:owner_note) { create(:note, author: owner, project: project) }
  let(:master_note) { create(:note, author: master, project: project) }
  let(:reporter_note) { create(:note, author: reporter, project: project) }
  let!(:notes) { [owner_note, master_note, reporter_note] }

  before do
    group.add_owner(owner)
    project.team << [master, :master]
    project.team << [reporter, :reporter]
    project.team << [guest, :guest]
  end

  describe "#notes_max_access_for_users" do
    it 'returns human access levels' do
      expect(helper.note_max_access_for_user(owner_note)).to eq('Owner')
      expect(helper.note_max_access_for_user(master_note)).to eq('Master')
      expect(helper.note_max_access_for_user(reporter_note)).to eq('Reporter')
    end

    it 'handles access in different projects' do
      second_project = create(:project)
      second_project.team << [master, :reporter]
      other_note = create(:note, author: master, project: second_project)

      expect(helper.note_max_access_for_user(master_note)).to eq('Master')
      expect(helper.note_max_access_for_user(other_note)).to eq('Reporter')
    end
  end

  describe '#note_first_contribution_for_user?' do
    let(:project) { create(:empty_project) }
    let(:other_project) { create(:empty_project) }

    let(:contributor) { create(:user) }
    let(:first_time_contributor) { create(:user) }

    # there should be a way to disable the lazy loading on these
    let(:merged_mr) { create(:merge_request, :merged, author: contributor, target_project: project, source_project: project) }
    let(:open_mr) { create(:merge_request, author: first_time_contributor, target_project: project, source_project: project) }
    let(:merged_mr_other_project) { create(:merge_request, :merged, author: first_time_contributor, target_project: other_project, source_project: other_project) }

    context "notes for a merge request" do
      let(:guest_merge_request) { create(:merge_request, author: guest, target_project: project, source_project: project) }
      let(:contributor_note) { create(:note, noteable: merged_mr, author: contributor, project: merged_mr.project) }
      let(:first_time_contributor_note) { create(:note, noteable: open_mr, author: first_time_contributor, project: open_mr.project) }
      let(:first_time_contributor_note_other_project) { create(:note, noteable: merged_mr_other_project, author: first_time_contributor, project: merged_mr_other_project.project) }
      let(:guest_note) { create(:note, noteable: guest_merge_request, author: first_time_contributor, project: project) }

      it "is true when you don't have any merged MR" do
        expect(helper.note_first_contribution_for_user? contributor_note).to be false
        expect(helper.note_first_contribution_for_user? first_time_contributor_note).to be true
      end

      it "handle multiple projects separately" do
        expect(helper.note_first_contribution_for_user? first_time_contributor_note).to be true
        expect(helper.note_first_contribution_for_user? first_time_contributor_note_other_project).to be false
      end

      it "should only apply to the noteable's author" do
        expect(helper.note_first_contribution_for_user? guest_note).to be false
      end
    end

    context "notes for an issue" do
      let(:guest_issue) { create(:issue, author: guest, project: project) }
      let(:contributor_issue) { create(:issue, author: contributor, project: project) }
      let(:first_time_contributor_issue) { create(:issue, author: first_time_contributor, project: project) }
      let(:first_time_contributor_issue_other_project) { create(:issue, author: first_time_contributor, project: other_project) }
        
      let(:contributor_note) { create(:note, noteable: contributor_issue, author: contributor, project: project) }
      let(:first_time_contributor_note) { create(:note, noteable: first_time_contributor_issue, author: first_time_contributor, project: project) }
      let(:first_time_contributor_note_other_project) { create(:note, noteable: first_time_contributor_issue_other_project, author: first_time_contributor, project: other_project) }
      let(:guest_note) { create(:note, noteable: guest_issue, author: first_time_contributor, project: project) }

      it "is true when you don't have any merged MR" do
        expect(merged_mr).to be
        expect(helper.note_first_contribution_for_user? contributor_note).to be false
        expect(helper.note_first_contribution_for_user? first_time_contributor_note).to be true
      end

      it "handle multiple projects separately" do
        expect(merged_mr).to be
        expect(merged_mr_other_project).to be
        expect(helper.note_first_contribution_for_user? first_time_contributor_note).to be true
        expect(helper.note_first_contribution_for_user? first_time_contributor_note_other_project).to be false
      end

      it "should only apply to the noteable's author" do
        expect(merged_mr).to be
        expect(helper.note_first_contribution_for_user? guest_note).to be false
      end
    end
  end

  describe '#discussion_path' do
    let(:project) { create(:project, :repository) }

    context 'for a merge request discusion' do
      let(:merge_request) { create(:merge_request, source_project: project, target_project: project, importing: true) }
      let!(:merge_request_diff1) { merge_request.merge_request_diffs.create(head_commit_sha: '6f6d7e7ed97bb5f0054f2b1df789b39ca89b6ff9') }
      let!(:merge_request_diff2) { merge_request.merge_request_diffs.create(head_commit_sha: nil) }
      let!(:merge_request_diff3) { merge_request.merge_request_diffs.create(head_commit_sha: '5937ac0a7beb003549fc5fd26fc247adbce4a52e') }

      context 'for a diff discussion' do
        context 'when the discussion is active' do
          let(:discussion) { create(:diff_note_on_merge_request, noteable: merge_request, project: project).to_discussion }

          it 'returns the diff path with the line code' do
            expect(helper.discussion_path(discussion)).to eq(diffs_project_merge_request_path(project, merge_request, anchor: discussion.line_code))
          end
        end

        context 'when the discussion is on an older merge request version' do
          let(:position) do
            Gitlab::Diff::Position.new(
              old_path: ".gitmodules",
              new_path: ".gitmodules",
              old_line: nil,
              new_line: 4,
              diff_refs: merge_request_diff1.diff_refs
            )
          end

          let(:diff_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: project, position: position) }
          let(:discussion) { diff_note.to_discussion }

          before do
            diff_note.position = diff_note.original_position
            diff_note.save!
          end

          it 'returns the diff version path with the line code' do
            expect(helper.discussion_path(discussion)).to eq(diffs_project_merge_request_path(project, merge_request, diff_id: merge_request_diff1, anchor: discussion.line_code))
          end
        end

        context 'when the discussion is on a comparison between merge request versions' do
          let(:position) do
            Gitlab::Diff::Position.new(
              old_path: ".gitmodules",
              new_path: ".gitmodules",
              old_line: 4,
              new_line: 4,
              diff_refs: merge_request_diff3.compare_with(merge_request_diff1.head_commit_sha).diff_refs
            )
          end

          let(:diff_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: project, position: position) }
          let(:discussion) { diff_note.to_discussion }

          before do
            diff_note.position = diff_note.original_position
            diff_note.save!
          end

          it 'returns the diff version comparison path with the line code' do
            expect(helper.discussion_path(discussion)).to eq(diffs_project_merge_request_path(project, merge_request, diff_id: merge_request_diff3, start_sha: merge_request_diff1.head_commit_sha, anchor: discussion.line_code))
          end
        end

        context 'when the discussion does not have a merge request version' do
          let(:outdated_diff_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: project, diff_refs: project.commit(sample_commit.id).diff_refs) }
          let(:discussion) { outdated_diff_note.to_discussion }

          before do
            outdated_diff_note.position = outdated_diff_note.original_position
            outdated_diff_note.save!
          end

          it 'returns nil' do
            expect(helper.discussion_path(discussion)).to be_nil
          end
        end
      end

      context 'for a legacy diff discussion' do
        let(:discussion) { create(:legacy_diff_note_on_merge_request, noteable: merge_request, project: project).to_discussion }

        context 'when the discussion is active' do
          before do
            allow(discussion).to receive(:active?).and_return(true)
          end

          it 'returns the diff path with the line code' do
            expect(helper.discussion_path(discussion)).to eq(diffs_project_merge_request_path(project, merge_request, anchor: discussion.line_code))
          end
        end

        context 'when the discussion is outdated' do
          before do
            allow(discussion).to receive(:active?).and_return(false)
          end

          it 'returns nil' do
            expect(helper.discussion_path(discussion)).to be_nil
          end
        end
      end

      context 'for a non-diff discussion' do
        let(:discussion) { create(:discussion_note_on_merge_request, noteable: merge_request, project: project).to_discussion }

        it 'returns nil' do
          expect(helper.discussion_path(discussion)).to be_nil
        end
      end
    end

    context 'for a commit discussion' do
      let(:commit) { discussion.noteable }

      context 'for a diff discussion' do
        let(:discussion) { create(:diff_note_on_commit, project: project).to_discussion }

        it 'returns the commit path with the line code' do
          expect(helper.discussion_path(discussion)).to eq(project_commit_path(project, commit, anchor: discussion.line_code))
        end
      end

      context 'for a legacy diff discussion' do
        let(:discussion) { create(:legacy_diff_note_on_commit, project: project).to_discussion }

        it 'returns the commit path with the line code' do
          expect(helper.discussion_path(discussion)).to eq(project_commit_path(project, commit, anchor: discussion.line_code))
        end
      end

      context 'for a non-diff discussion' do
        let(:discussion) { create(:discussion_note_on_commit, project: project).to_discussion }

        it 'returns the commit path' do
          expect(helper.discussion_path(discussion)).to eq(project_commit_path(project, commit))
        end
      end
    end
  end

  describe '#notes_url' do
    it 'return snippet notes path for personal snippet' do
      @snippet = create(:personal_snippet)

      expect(helper.notes_url).to eq("/snippets/#{@snippet.id}/notes")
    end

    it 'return project notes path for project snippet' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      @snippet = create(:project_snippet, project: @project)
      @noteable = @snippet

      expect(helper.notes_url).to eq("/nm/test/noteable/project_snippet/#{@noteable.id}/notes")
    end

    it 'return project notes path for other noteables' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      @noteable = create(:issue, project: @project)

      expect(helper.notes_url).to eq("/nm/test/noteable/issue/#{@noteable.id}/notes")
    end
  end

  describe '#note_url' do
    it 'return snippet notes path for personal snippet' do
      note = create(:note_on_personal_snippet)

      expect(helper.note_url(note)).to eq("/snippets/#{note.noteable.id}/notes/#{note.id}")
    end

    it 'return project notes path for project snippet' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      note = create(:note_on_project_snippet, project: @project)

      expect(helper.note_url(note)).to eq("/nm/test/notes/#{note.id}")
    end

    it 'return project notes path for other noteables' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      note = create(:note_on_issue, project: @project)

      expect(helper.note_url(note)).to eq("/nm/test/notes/#{note.id}")
    end
  end

  describe '#form_resources' do
    it 'returns note for personal snippet' do
      @snippet = create(:personal_snippet)
      @note = create(:note_on_personal_snippet)

      expect(helper.form_resources).to eq([@note])
    end

    it 'returns namespace, project and note for project snippet' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      @snippet = create(:project_snippet, project: @project)
      @note = create(:note_on_personal_snippet)

      expect(helper.form_resources).to eq([@project.namespace, @project, @note])
    end

    it 'returns namespace, project and note path for other noteables' do
      namespace = create(:namespace, path: 'nm')
      @project = create(:project, path: 'test', namespace: namespace)
      @note = create(:note_on_issue, project: @project)

      expect(helper.form_resources).to eq([@project.namespace, @project, @note])
    end
  end

  describe '#noteable_note_url' do
    let(:project) { create(:project) }
    let(:issue) { create(:issue, project: project) }
    let(:note) { create(:note_on_issue, noteable: issue, project: project) }

    it 'returns the noteable url with an anchor to the note' do
      expect(noteable_note_url(note)).to match("/#{project.namespace.path}/#{project.path}/issues/#{issue.iid}##{dom_id(note)}")
    end
  end

  describe '#discussion_resolved_intro' do
    context 'when the discussion was resolved by a push' do
      let(:discussion) { double(:discussion, resolved_by_push?: true) }

      it 'returns "Automatically resolved"' do
        expect(discussion_resolved_intro(discussion)).to eq('Automatically resolved')
      end
    end

    context 'when the discussion was not resolved by a push' do
      let(:discussion) { double(:discussion, resolved_by_push?: false) }

      it 'returns "Resolved"' do
        expect(discussion_resolved_intro(discussion)).to eq('Resolved')
      end
    end
  end
end
