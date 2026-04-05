-- Grouped inventory view: stacks cards by master_card_id + grade
-- Each row = one (card identity × condition) combination per user.
-- Used for analytics; the Angular app builds stacks client-side from user_cards.
CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
SELECT
  u.user_id,
  m.id                          AS master_card_id,
  m.player,
  m.parallel_type,
  s.name                        AS set_name,
  s.year,
  s.sport,
  u.is_graded,
  u.grader,
  u.grade_value,
  count(u.id)                   AS quantity,
  sum(u.price_paid)             AS total_cost,
  avg(u.price_paid)             AS avg_cost,
  sum(u.current_value)          AS total_value,
  avg(u.current_value)          AS market_value_per_card
FROM public.user_cards u
JOIN public.master_card_definitions m ON u.master_card_id = m.id
LEFT JOIN public.sets s ON m.set_id = s.id
GROUP BY
  u.user_id,
  m.id,
  m.player,
  m.parallel_type,
  s.name,
  s.year,
  s.sport,
  u.is_graded,
  u.grader,
  u.grade_value;
