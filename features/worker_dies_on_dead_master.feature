Feature: worker dies on dead master

  As a worker
  I want to commit suicide when my master dies
  So that I won't become a zombie process

  Scenario Outline: workers
    Given there are <n> <type> workers
    When the master dies
    Then all workers should die within a minute

    Scenarios:
      | n  | type     |
      | 1  | base     |
      | 5  | base     |
      | 10 | base     |
      | 1  | thin     |
      | 5  | thin     |
      | 10 | thin     |
      | 1  | mongrel2 |
      | 5  | mongrel2 |
      | 10 | mongrel2 |
      | 1  | eventd   |
      | 5  | eventd   |
      | 10 | eventd   |