# AMOS Login Information

Quick reference for accessing the application in Docker.

---

## 🚀 Application URL

```
http://localhost:3000
```

---

## 🔐 Login Credentials

**All users have the same password:** `password123`

### Available Accounts

| Email | Password | Role | Entity |
|-------|----------|------|--------|
| `test@example.com` | `password123` | Admin | Test Entity Two |
| `user1@test.com` | `password123` | Admin | Test Entity One |
| `user2@test.com` | `password123` | Marketer | Test Entity One |
| `default@test.com` | `password123` | Admin | Default Test Entity |

### Recommended for Testing

**Primary Test Account:**
- Email: `test@example.com`
- Password: `password123`
- Role: Admin (full access)

---

## 🔧 Reset Passwords

If you need to reset passwords again:

```bash
docker-compose exec web rails runner scripts/reset_all_passwords.rb
```

This will set all user passwords to `password123`.

---

## 🆕 Create New Test User

To create additional test users:

```bash
docker-compose exec web rails console
```

Then:
```ruby
entity = Entity.first

User.create!(
  email: 'newuser@example.com',
  password: 'password123',
  password_confirmation: 'password123',
  first_name: 'New',
  last_name: 'User',
  entity: entity,
  onboarded: true,
  role: 'admin'  # or 'marketer'
)
```

---

## 🔍 Verify Login Works

```bash
docker-compose exec web rails runner scripts/create_test_user.rb
```

This will:
- Show all users
- Verify passwords
- Display login credentials

---

## 🐛 Troubleshooting

### "Invalid email or password"

**Try:**
1. Reset all passwords:
   ```bash
   docker-compose exec web rails runner scripts/reset_all_passwords.rb
   ```

2. Verify user exists:
   ```bash
   docker-compose exec web rails console
   ```
   ```ruby
   User.find_by(email: 'test@example.com')
   ```

3. Check app logs:
   ```bash
   docker-compose logs -f web
   ```

### "Connection refused"

**Check Docker is running:**
```bash
docker-compose ps
```

**Restart if needed:**
```bash
docker-compose restart web
```

### "Page not loading"

**Verify Rails is running:**
```bash
curl http://localhost:3000
```

Should return HTML or redirect (not "Connection refused")

---

## 📊 Entity Information

The app has 3 test entities for multi-tenant testing:

1. **Test Entity One** (ID: 980190962)
   - Users: `user1@test.com`, `user2@test.com`

2. **Test Entity Two** (ID varies)
   - Users: `test@example.com`

3. **Default Test Entity** (ID: 593363170)
   - Users: `default@test.com`

Each entity has isolated data (campaigns, contacts, RAG stores, etc.)

---

## 🧪 Testing RAG with Logged-In User

Once logged in, you can test RAG:

1. **Go to Scout** (AI chat interface)
2. **Upload a document** (requires API keys)
3. **Ask questions** about the document

**Note:** RAG requires valid API keys:
- `OPENAI_API_KEY` in `.env`
- `PINECONE_API_KEY` in `.env`

---

## 📝 Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/create_test_user.rb` | Create test@example.com user |
| `scripts/reset_all_passwords.rb` | Reset all passwords to password123 |

---

**Last Updated:** 2025-10-18
**Default Password:** `password123` (all users)
