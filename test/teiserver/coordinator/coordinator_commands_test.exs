defmodule Teiserver.Coordinator.CoordinatorCommandsTest do
  use Central.ServerCase, async: false
  alias Teiserver.{User, Coordinator, Account}

  import Teiserver.TeiserverTestLib,
    only: [tachyon_auth_setup: 0, _tachyon_send: 2, _tachyon_recv: 1, new_user: 0]

  setup do
    Coordinator.start_coordinator()
    %{socket: socket, user: user} = tachyon_auth_setup()

    coordinator_userid = Coordinator.get_coordinator_userid()

    {:ok, socket: socket, user: user, coordinator_userid: coordinator_userid}
  end

  test "no command", %{socket: socket} do
    message_coordinator(socket, "$no_command_here or here")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    # It's not a valid command and thus we ignore it currently
    reply = _tachyon_recv(socket)
    assert reply == :timeout
  end

  test "whoami", %{socket: socket, user: user, coordinator_userid: coordinator_userid} do
    message_coordinator(socket, "$whoami")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => ["You are #{user.name}", "Rank: 1 with 0 player hours and 0 spectator hours for a rank hour count of 0", "You currently have no accolades"],
      "sender_id" => coordinator_userid
    }
  end

  test "whois", %{socket: socket, coordinator_userid: coordinator_userid} do
    other_user = new_user()

    message_coordinator(socket, "$whois #{other_user.name}")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => ["Found #{other_user.name}"],
      "sender_id" => coordinator_userid
    }

    # Now with previous names
    Account.update_user_stat(other_user.id, %{
      "previous_names" => ["name1", "name2"]
    })

    message_coordinator(socket, "$whois #{other_user.name}")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => ["Found #{other_user.name}", "Previous names: name1, name2"],
      "sender_id" => coordinator_userid
    }
  end

  test "mute user command", %{socket: socket, user: user, coordinator_userid: coordinator_userid} do
    %{user: user2} = tachyon_auth_setup()

    message_coordinator(socket, "$mute #{user2.name}")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => "#{user2.name} is now ignored, you can unmute them with the $unignore command or via the relationships section of the website.",
      "sender_id" => coordinator_userid
    }

    user = User.get_user_by_id(user.id)
    assert user.ignored == [user2.id]

    # Now use it again, make sure we don't get a crash
    message_coordinator(socket, "$unmute #{user2.name}")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => "#{user2.name} is now un-ignored.",
      "sender_id" => coordinator_userid
    }

    user = User.get_user_by_id(user.id)
    assert user.ignored == []

    # Now unmute again
    message_coordinator(socket, "$unmute #{user2.name}")
    [reply] = _tachyon_recv(socket)
    assert reply == %{"cmd" => "s.lobby.send_direct_message", "result" => "success"}

    [reply] = _tachyon_recv(socket)
    assert reply == %{
      "cmd" => "s.communication.received_direct_message",
      "message" => "#{user2.name} is now un-ignored.",
      "sender_id" => coordinator_userid
    }

    user = User.get_user_by_id(user.id)
    assert user.ignored == []
  end

  defp message_coordinator(socket, message) do
    _tachyon_send(socket, %{
      cmd: "c.communication.send_direct_message",
      message: message,
      recipient_id: Coordinator.get_coordinator_userid()
    })
  end
end