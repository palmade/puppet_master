Feature: master can be stopped

  As a user
  I want to stop the master
  So that it will stop serving me

  Scenario: stopping a running instance
    Given a puppet_master instance is running
    When I run `ruby script/appctl stop`
    Then it should pass with:
    """
    Sending QUIT
    """
    Then there should be no instance running
    And all workers should die within a minute
    And the file "tmp/pids/appctl.pid" should not exist

  Scenario: no instance to stop
    Given puppet_master has been configured
    And there are no other instances running
    When I run `ruby script/appctl stop`
    Then it should fail with:
    """
    aborted, not running
    """
