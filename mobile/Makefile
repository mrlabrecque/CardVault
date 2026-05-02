SUPABASE_URL=https://bqwfyxthnoxcbvgchbyh.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxd2Z5eHRobm94Y2J2Z2NoYnloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzMTA4MDMsImV4cCI6MjA5MDg4NjgwM30.XpHsrnwB1KZjUbHuZ2lj-xfGshPSFSZ_Kxdiso-kTLk

DART_DEFINES=--dart-define=SUPABASE_URL=$(SUPABASE_URL) --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY)

.PHONY: ipa run

ipa:
	flutter build ipa --release $(DART_DEFINES)

run:
	flutter run $(DART_DEFINES)
