# Eventd - A database for event sourcing

## Feature Goals

- Event types are first class citizens that are defined up front with strong schemas
- Event field data types should be as close to postgres types as possible
- Events are submitted to a stream
- Stream paths are RESTlike and should contain primary key(s) which correspond to events
- Streams can be subscribed to
- Subscriptions can be filtered by using wildcards in the stream path
- Aggregates are first class citizens similar to regular db tables
- Aggregates schemas / fields should be as close to postgres types as possible
- Aggregates can be queried with SQL and can be joined together
- Aggregates can be subscribed to (basically a stream whose events are updates to the aggregate)
- Aggregate subscriptions can be filtered similar to streams
- Events can contain fields that belong to an aggregate
- Events can contain fields from multiple aggregates (not 100% on this)
- When a event with a field from an aggregate is submitted, the aggregate is updated with the value(s)
- The database can be run as a single node or clustered
- The database can be run as an edge node
- If running as an edge node, at startup specify which events / streams / aggregates should be synced
- Edge nodes can be run as wasm and embedded in other applications (including on the frontend)
- Migrations are first class citizens. Migrations are the hardest part of event sourcing and we need to have an answer for it

## Examples

- Create an account aggregate

```sql
CREATE AGGREGATE account (
    id          SERIAL PRIMARY KEY,
    name        varchar(40) NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT NOW(),
)
```

- Create a billing contact aggregate

```sql
CREATE AGGREGATE billing_contact (
    id          SERIAL PRIMARY KEY,
    first_name  varchar(40) NOT NULL,
    last_name   varchar(40) NOT NULL,
    account_id  references account(id)
)
```

 - Create an account_type event type that references the account aggregate. Since the id is specified as `creates account(id)`, it will auto increment and insert a new record into the account aggregate (TODO - not sure what the best approach is for specifying auto incrementing keys / things that create new aggregate records. Notice the send_notification field is not tied to the aggregate so must be fully specified. Also has fields tied to the billing contact aggregate (not sure if this is good)

```sql
CREATE EVENT_TYPE account_created (
    id                  creates account(id),
    name                updates account(name),
    created_at          updates account(created_at),
    billing_id          creates billing_contact(id)
    billing_first_name  updates billing_contact(first_name)
    billing_last_name   updates billing_contact(first_name)
    send_notification   boolean NOT NULL,
)
```

- Create an event that updates an account name

```sql
CREATE EVENT_TYPE account_name_updated (
    id                  references account(id),
    name                updates account(name),
)

```

- Create a stream for new accounts

```sql
CREATE STREAM account_events (
    path         "/accounts/{id}" -- `{id}` specifies that the events in this stream must have an `id` field to allow subscription filtering
    event_types  (account_created, account_name_updated)
)
```

- Posting an account_created event to a stream. Notice that `id`, `billing_id` and `created_at` are not specified so the database will default them

```http
POST http://localhost:5678/streams/account_events
Content-Type: application/json
XEvent-Type: account_created
 
{
  "name":"test account",
  "billing_first_name": "Bob",
  "billing_last_name": "Test",
  "send_notification": true,
}
```

- Posting an account_name_updated event to a stream. Notice that we must provide the account id now. It can be provided in either the body, or the path, or both.

```http
POST http://localhost:5678/streams/account_events/123
Content-Type: application/json
XEvent-Type: account_name_updated
 
{
  "account_id": 123,
  "name": "test account 2"
}
```


TODO: Subscriptions


## Technical Goals
- 0 Dependencies
- Performance on par with just using postgres for event sourcing
- All memory is allocated at startup
- Make use of NASA's power of 10 rules for writing safe code (not all 10 apply to Zig)
- Rely on the type system as much as possible
- Make use of deterministic simulation testing and fuzzing
- All IO must go through an interface (allows deterministic simulation testing and helps future proof against the coming changes to Zig async which will force this)
- The underlying storage engine must be swappable. (I am sure it won't be right the first time)
- Minimize resource usage. Goal is to be simple and small - think sqlite of event sourcing at least when running in edge mode
