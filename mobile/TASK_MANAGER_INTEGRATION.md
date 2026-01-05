# Task Manager Integration Guide

## 🎯 Overview

The mobile app now has **complete task management infrastructure** with support for:
- ✅ Full task CRUD operations
- ✅ Filtering by status, priority, due date
- ✅ Task assignment and tracking
- ✅ Related entity linking (campaigns, contacts, landing pages)
- ✅ Task statistics and dashboards
- ✅ Redux state management
- ⏳ UI Screens (ready to build)
- ⏳ Chat integration (ready to implement)
- ⏳ Home widget (ready to implement)

---

## 📁 Implementation Architecture

### 1. **Type Definitions** ✅
**File**: `src/types/index.ts`
```typescript
// Task interfaces
- Task: Core task data
- TaskDetail: Task with comments/attachments
- TaskComment: Comments on tasks
- TaskAttachment: File attachments

// Redux State
- tasks state with list, current, filters, pagination
```

### 2. **API Service Layer** ✅
**File**: `src/services/tasks.ts`

**Available Methods**:
- `getTasks()` - Fetch with pagination and filters
- `getTask(id)` - Get single task detail
- `createTask(data)` - Create new task
- `updateTask(id, data)` - Update task
- `completeTask(id)` - Mark as complete
- `deleteTask(id)` - Delete task
- `getTasksByEntity()` - Get tasks for campaign/contact/landing page
- `getTasksDueToday()` - Get today's tasks
- `getOverdueTasks()` - Get overdue tasks
- `getTaskStats()` - Get dashboard statistics

### 3. **Redux State Management** ✅
**File**: `src/store/slices/tasksSlice.ts`

**Async Thunks**:
- `fetchTasks` - Load tasks list with filters
- `fetchTaskDetail` - Load single task
- `createTask` - Create task
- `updateTaskAsync` - Update task
- `completeTaskAsync` - Mark complete
- `deleteTaskAsync` - Delete task
- `fetchTasksDueToday` - Load today's tasks
- `fetchOverdueTasks` - Load overdue tasks

**Actions**:
- `setFilters` - Update filter state
- `clearFilters` - Reset filters
- `clearCurrentTask` - Clear detail view

### 4. **Redux Store Integration** ✅
**File**: `src/store/index.ts`
- Tasks reducer added to store
- Full type safety with Redux Toolkit

---

## 📱 UI Components (Ready to Build)

### Screen 1: TaskListScreen
**Location**: `src/screens/tasks/TaskListScreen.tsx`

**Features**:
- List all tasks with cards
- Search by title/description
- Filter by:
  - Priority (High/Medium/Low)
  - Status (Pending/In Progress/Completed)
  - Due date range
- Quick complete button on each card
- Pull-to-refresh
- Tap to view detail
- FAB to create new task

**Key Components**:
- Task cards with status, priority, due date badges
- Filter modal
- Search input
- Empty state

### Screen 2: TaskDetailScreen
**Location**: `src/screens/tasks/TaskDetailScreen.tsx`

**Features**:
- Full task information display
- Status management dropdown
- Priority display and edit
- Due date picker
- Related entity display (campaign/contact/page)
- Comments section (if implemented)
- Attachments list
- Actions menu:
  - Edit
  - Complete
  - Delete
  - Archive

**Key Components**:
- Task header with title
- Status/Priority badges
- Due date display
- Related entity card
- Comments section
- Action buttons

### Screen 3: TaskEditScreen
**Location**: `src/screens/tasks/TaskEditScreen.tsx`

**Features**:
- Create new or edit existing task
- Form fields:
  - Title (required)
  - Description
  - Priority selector
  - Status selector
  - Due date picker
  - Assign to (user selector)
  - Related entity selector
  - Tags input
- Form validation
- Save/Cancel buttons

---

## 🏠 Home Screen Widget

**Location**: `src/screens/home/HomeScreen.tsx` (modify existing)

**New Widget**:
```tsx
<TaskWidget>
  - Today's tasks count
  - Overdue tasks badge (red)
  - Quick actions:
    - "3 tasks due today"
    - "2 overdue"
  - "Create task" button
  - Recent task activity
</TaskWidget>
```

**Integration Points**:
- Add to home screen below analytics
- Use `fetchTasksDueToday()` and `fetchOverdueTasks()`
- Show tasks with blue/red badges

---

## 💬 Chat Integration

**Location**: `src/screens/chat/ChatScreen.tsx` (modify existing)

**New Features**:
- Add "Create Task" button in chat actions menu
- Use bottom sheet to create task from message:
  - Auto-populate title from selected message
  - Quick priority/due date selection
  - Create button
  - Cancel button

**Implementation**:
```tsx
const handleCreateTaskFromMessage = async (message: ChatMessage) => {
  // Show task creation bottom sheet
  // Pre-fill title with message content
  // User sets priority, due date
  // Call createTask() thunk
}
```

---

## 🔗 Navigation Integration

**Add to Navigation**:
```tsx
// Bottom Tab or Stack Navigator
<Tab.Screen name="Tasks" component={TaskListScreen} />

// Nested Stack
<Stack.Screen name="TaskDetail" component={TaskDetailScreen} />
<Stack.Screen name="TaskEdit" component={TaskEditScreen} />
```

**Deep Linking**:
```
tasks://list
tasks://create
tasks/:id (detail)
tasks/:id/edit
```

---

## 🧪 Testing Strategy

### Unit Tests
**Files to create**:
- `__tests__/screens/TaskListScreen.test.tsx`
- `__tests__/screens/TaskDetailScreen.test.tsx`
- `__tests__/screens/TaskEditScreen.test.tsx`

**Test Cases**:
- Loading states
- Rendering tasks
- Filtering and search
- Status updates
- Completion actions
- Error handling
- Navigation
- Form validation

### E2E Tests
**File**: `e2e/taskWorkflow.e2e.js`

**Scenarios**:
- Create task from list view
- View task detail
- Complete task
- Edit task
- Delete task
- Filter tasks
- Search tasks
- Create task from chat
- Create task from campaign detail

---

## 📊 Data Flow Diagram

```
ChatScreen
    ↓
  [Create Task Modal]
    ↓
createTask() action
    ↓
tasks.ts service
    ↓
API: POST /api/v1/tasks
    ↓
Redux store update
    ↓
TaskListScreen refresh
```

---

## 🚀 Implementation Checklist

- [x] Types (src/types/index.ts)
- [x] Service (src/services/tasks.ts)
- [x] Redux Slice (src/store/slices/tasksSlice.ts)
- [x] Store Integration (src/store/index.ts)
- [ ] TaskListScreen (src/screens/tasks/TaskListScreen.tsx)
- [ ] TaskDetailScreen (src/screens/tasks/TaskDetailScreen.tsx)
- [ ] TaskEditScreen (src/screens/tasks/TaskEditScreen.tsx)
- [ ] Home Widget (modify src/screens/home/HomeScreen.tsx)
- [ ] Chat Integration (modify src/screens/chat/ChatScreen.tsx)
- [ ] Navigation Integration (src/navigation/)
- [ ] Unit Tests (__tests__/screens/)
- [ ] E2E Tests (e2e/taskWorkflow.e2e.js)
- [ ] Documentation

---

## 💡 Quick Start Guide

### Step 1: View Tasks
```bash
// Navigate to Tasks tab
// Dispatch: fetchTasks({ page: 1, perPage: 20 })
// Component: TaskListScreen
```

### Step 2: Create Task
```bash
// Click FAB in TaskListScreen
// Fill TaskEditScreen form
// Dispatch: createTask(taskData)
// Service: POST /api/v1/tasks
```

### Step 3: Complete Task
```bash
// In TaskListScreen or TaskDetailScreen
// Click complete button
// Dispatch: completeTaskAsync(taskId)
// Service: PATCH /api/v1/tasks/:id
```

### Step 4: From Chat
```bash
// In ChatScreen
// Long-press message or click action menu
// "Create Task" → Task Creation Modal
// Dispatch: createTask(taskData)
```

---

## 📝 API Endpoints Expected

```
GET    /api/v1/tasks                    # List with filters
GET    /api/v1/tasks/:id                # Detail
POST   /api/v1/tasks                    # Create
PATCH  /api/v1/tasks/:id                # Update
DELETE /api/v1/tasks/:id                # Delete
GET    /api/v1/tasks/due-today          # Today's tasks
GET    /api/v1/tasks/overdue            # Overdue tasks
GET    /api/v1/tasks/stats              # Statistics
GET    /api/v1/tasks/entity/:type/:id   # By entity
```

---

## 🎨 UI/UX Standards

All task screens follow existing patterns:
- Dark mode support via `getColors(theme)`
- Redux state management with typed selectors
- Error handling with retry buttons
- Loading states with spinners
- Pull-to-refresh on list
- Consistent navigation patterns
- Swipe-to-delete support (using SwipeableListItem)
- Form validation with error messages

---

## 📦 Dependencies

No new dependencies required - uses existing:
- Redux Toolkit
- React Navigation
- React Native
- Expo

---

## 🔒 Security Notes

- JWT auth inherited from API client
- Task access controlled by backend (entity scoping)
- Form validation on client and server
- No sensitive data in Redux (server-managed)

---

## 📞 Support

For questions about:
- **Types**: See `src/types/index.ts`
- **API**: See `src/services/tasks.ts`
- **Redux**: See `src/store/slices/tasksSlice.ts`
- **Components**: Following existing screen patterns

---

**Status**: Infrastructure Complete ✅ | Screens Ready to Build ⏳
