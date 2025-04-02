-- Understanding the data structures
SELECT bill_id, bill_type, bill_number, congress, title, status
FROM analyst.bills;

SELECT committee_id, bill_id
FROM analyst.bills_committees;

SELECT client_id, client_name
FROM analyst.clients;

SELECT committee_id, "type", committee_name
FROM analyst.committees;

SELECT filing_uuid, registrant_id, client_id, amount, filing_year, filing_period_code, filing_period_display
FROM analyst.filings;

SELECT filing_uuid, general_issue_code, bill_id
FROM analyst.filings_bills;

SELECT filing_uuid, general_issue_code
FROM analyst.filings_issues;

SELECT general_issue_code, general_issue_name
FROM analyst.issue_codes;

SELECT registrant_id, registrant_name
FROM analyst.registrants;

-- Data quality checks --
-- So we know there are no duplicates between IDs and names
-- for both registrants and clients
-- then we don't need to worry about this causing any issues
-- in prod would have more defensive programing in the queries
-- and follow it up with additional defenses in dbt configs & tests
with no_duplicate_registrants as (
select
	registrant_id,
	registrant_name,
	count(*) as num
from
	analyst.registrants r
group by
	registrant_id,
	registrant_name)
select
	count(num) as registrant_occurences
from
	no_duplicate_registrants
	
with no_duplicate_clients as (
select
	client_id,
	client_name,
	count(*) as num
from
	analyst.clients c
group by
	client_id,
	client_name)
select
	count(num) as client_occurences
from
	no_duplicate_clients

-- Question #1
-- Simple.
select
	r.registrant_name,
	sum(f.amount) as total_amount
from
	analyst.registrants r
left join analyst.filings f
on
	r.registrant_id = f.registrant_id
group by
	r.registrant_name
having
	sum(f.amount) > '$10,000,000.00'
order by
	sum(f.amount) desc

-- Question #2
-- This question has two steps so I think I will break it down into CTEs.
-- I can modify my last question's sql statement into the first CTE.
with top5_registrants as(
select
	r.registrant_id,
	r.registrant_name,
	sum(f.amount) as registrant_amount
from
	analyst.registrants r
left join analyst.filings f
on
	r.registrant_id = f.registrant_id
group by
	r.registrant_id, r.registrant_name
having
	sum(f.amount) is not null
order by
	registrant_amount desc
limit 5
),
-- Now let's look at filed payments by client
top5_registrants_client_payments as (
select
	t.registrant_id,
	t.registrant_name,
	t.registrant_amount,
	f.client_id,
	c.client_name,
	sum(f.amount) as client_amount,
	count(f.amount) as client_filed_payments,
	-- for internal ranking
	row_number() over (partition by t.registrant_id order by sum(f.amount) desc) as client_amount_rank
from
	top5_registrants t
left join analyst.filings f
on
	t.registrant_id = f.registrant_id
left join analyst.clients c 
on
	f.client_id = c.client_id
group by
	t.registrant_id,
	registrant_name,
	t.registrant_amount,
	f.client_id,
	c.client_name
having
	sum(f.amount) is not null
	)
select
	registrant_name,
	client_name,
	client_amount,
	client_amount_rank
from
	top5_registrants_client_payments
where
	client_amount_rank <= 5
order by
	registrant_amount desc,
	client_amount_rank asc


-- A lot of those registrants had only one client
-- so I double check that I am not mucking something up.
select
	registrant_id,
	count(distinct(client_id)) as distinct_client_count
from
	analyst.filings
where
	registrant_id in (38756, 27070, 51172, 27354, 682)
group by
	registrant_id

-- Also it was odd AKIN (682) was above NCTA
-- thinking it through it is because it's filing amount must be higher
-- but is truncated by the 5 client limit. Let's verify!
select
	registrant_id,
	sum(amount) as total_amount
from
	analyst.filings
where
	registrant_id = 682
group by
	registrant_id


-- Question #3
-- Here I would approach this by first pulling the top
-- MMM registrant then joining the distinct bills onto that.
-- In R I would use mutate group bys to get totals then filter.
-- The equivalent here would be an "over partition by ... order by ..."
-- but tragically I have learned window functions don't support distinct.
with top_mmm_registrant as (
select
	r.registrant_id,
	count(distinct(bill_id)) as distinct_bills
from
	analyst.registrants r
inner join analyst.filings f
on
	r.registrant_id = f.registrant_id
inner join analyst.filings_bills fb
on
	f.filing_uuid = fb.filing_uuid
	and fb.general_issue_code = 'MMM'
group by
	registrant_name,
	r.registrant_id
order by
	distinct_bills desc
limit 1
)
select
	distinct
bill_id
from
	top_mmm_registrant t
inner join analyst.filings f
on
	t.registrant_id = f.registrant_id
left join analyst.filings_bills fb
on
	f.filing_uuid = fb.filing_uuid
	and fb.general_issue_code = 'MMM'

-- Actually bills can appear multiple times in a filing
-- looks due to their general issue code, so it shouldn't matter
-- here but verifying for this specific case.
select 
  filing_uuid, 
  general_issue_code,
  bill_id, 
  count(*) AS appearances
from 
  analyst.filings_bills
where
  general_issue_code = 'MMM'
group by 
  filing_uuid, 
  general_issue_code,
  bill_id
having 
  count(*) > 1

-- Question #4
-- Sounds straightforward. 
-- Hmm do any bill share titles in this table?
with title_occurences as (
select
	count(title) as title_count
from
	analyst.bills
group by
	title
)
select
	title_count,
	count(title_count) as occurences
from
	title_occurences
group by
	title_count
order by
	title_count

-- I'll do regular expressions here.
-- Should lookup other postgresql string functions & operators that are more efficent.
-- But this is a solution that I am comfortable with.
select
	count(case when title ~* '(Act|Law|Resolution)$' then title else null end) as standard_titles,
	count(case when title ~* '(Act|Law|Resolution)$' then null else title end) as non_standard_titles
from
	analyst.bills

-- But does the "of 2XXX" ending count as standard? Looking through bill titles that format is very common.
-- The language of the question seems to exclude this, but let's see its frequency to judge if it is standard.
select
	count(case when title ~* 'of 2\d{3}$' then title else null end) as ending_in_of_year
from
	analyst.bills

-- I mean arguably to me this format seems frequent enough to be a standard title convention.
-- Are there bills older than 2000 in here as well? Should probably look at the dates
-- but this is an expedient check. In fact more fitting for this use case.
select
	distinct title
from
	analyst.bills
where
	title ~* 'of \d{4}$'
	and title !~* 'of 2'

-- Well I deem this format frequent enough to be standard.
-- So here is a bonus query for what if we counted that ending as standard:
select
	count(case when title ~* '(Act|Law|Resolution)( of [12]\d{3})?$' then title else null end) as standard_titles,
	count(case when title ~* '(Act|Law|Resolution)( of [12]\d{3})?$' then null else title end) as non_standard_titles
from
	analyst.bills

