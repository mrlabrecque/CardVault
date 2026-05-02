SUPABASE_URL=https://bqwfyxthnoxcbvgchbyh.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxd2Z5eHRobm94Y2J2Z2NoYnloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzMTA4MDMsImV4cCI6MjA5MDg4NjgwM30.XpHsrnwB1KZjUbHuZ2lj-xfGshPSFSZ_Kxdiso-kTLk

# Google OAuth — get these from Google Cloud Console > APIs & Services > Credentials
# Web client ID goes in Supabase Dashboard > Auth > Providers > Google
# iOS client ID comes from GoogleService-Info.plist (REVERSED_CLIENT_ID also needed in Info.plist)
GOOGLE_WEB_CLIENT_ID=791086653690-9gv7l68ne6vackl9r2q2nvd08h8mue3k.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=791086653690-r7e915md5h1v718lrblnq3jc4638j9ha.apps.googleusercontent.com

DART_DEFINES=--dart-define=SUPABASE_URL=$(SUPABASE_URL) --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) --dart-define=GOOGLE_WEB_CLIENT_ID=$(GOOGLE_WEB_CLIENT_ID)

.PHONY: ipa run

ipa:
	@VERSION=$$(grep '^version:' pubspec.yaml | sed 's/version: //'); \
	NAME=$$(echo $$VERSION | cut -d'+' -f1); \
	BUILD=$$(echo $$VERSION | cut -d'+' -f2); \
	NEW_BUILD=$$((BUILD + 1)); \
	sed -i '' "s/^version: .*/version: $$NAME+$$NEW_BUILD/" pubspec.yaml; \
	echo "Building $$NAME+$$NEW_BUILD..."; \
	flutter build ipa --release $(DART_DEFINES)

run:
	flutter run $(DART_DEFINES)
