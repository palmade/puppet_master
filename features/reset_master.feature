Feature: master can be reset

  As a user
  I want to reset the master
  So that it reload the application code

  Scenario: restart a running instance
    Given a puppet_master instance is running
    When I run `ruby script/appctl restart`
    Then it should pass with:
    """
    Sending USR1
    """
    Then there should be a new instance running
    And the old instance should have its arg list indicated as such
    And the old instance should die within a minute

  Scenario: no instance to restart
    Given puppet_master has been configured
    And there are no other instances running
    When I run `ruby script/appctl restart`
    Then it should fail with:
    """
    aborted, not running
    """
