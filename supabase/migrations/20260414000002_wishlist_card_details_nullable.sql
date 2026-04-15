-- card_details is superseded by normalized columns; drop the not-null constraint.
alter table wishlist alter column card_details drop not null;
