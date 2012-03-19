
create extension if not exists hstore;

--begin;

-- Test table
drop table if exists foos;
create table foos (
  id serial primary key,
  name text not null,
  slug text,
  slug_history hstore default ''
);

/* Should we have a separate slug column?
 * Could define #slug to grab the first element in slug_history
 * Would save space on large tables. */

create index on foos using gin(slug_history);

create or replace function sluggify(text) returns text as $$
  select lower(regexp_replace($1, '[^a-zA-Z0-9]', '-', 'g'));
$$ language sql immutable;

create or replace function search_slug_history(search_term text, search_column hstore) returns boolean as $$
  select $2 ? $1;
$$ language sql immutable;

-- Updates the slug
create or replace function update_slug() returns trigger as $$
declare
  slug_column text;
  new_slug_value text;
  already_exists integer;
  the_same boolean;
  results foos%rowtype;
begin
  slug_column := TG_ARGV[0];

  execute 'select sluggify($1.' || slug_column || ')' into new_slug_value using new;

  if TG_OP = 'UPDATE' then
    execute 'select $1 = $2.' || slug_column into the_same using new_slug_value, old;
    if the_same then
      return NEW;
    end if;
  end if;

  execute 'select count(*) from (select unnest(avals(slug_history)::integer[]) x from ' || tg_table_name || ' where search_slug_history($1, slug_history)) f'
    into already_exists using new_slug_value;

  already_exists := already_exists + 1;

  NEW.slug := new_slug_value || '--' || already_exists;
  NEW.slug_history := NEW.slug_history || ARRAY[new_slug_value, already_exists::text]::hstore;

  return NEW;
end;
$$ language plpgsql;

create trigger sluggerize_foos 
before insert or update of name on foos
for each row execute procedure update_slug('name');

insert into foos (name) values ('Joe Product');
insert into foos (name) values ('Joe Product 1');
insert into foos (name) values ('Another Product');

update foos set name = 'Blah Product' where name = 'Joe Product';
update foos set name = 'BLAH PRODUCT' where name = 'Blah Product';

select * from foos;

insert into foos (name) values ('Joe Product');
insert into foos (name) values ('JOE PRODUCT');
--update foos set name = 'Joe Product';

select * from foos;
