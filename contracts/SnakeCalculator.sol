// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SnakeCalculator - a playful mashup of a snake mini game and a basic calculator
/// @author Generated
/// @notice The contract lets every address control an individual snake board and use an on-chain
/// calculator that can optionally boost the current score.
contract SnakeCalculator {
    uint8 public constant MIN_BOARD_SIZE = 4;
    uint8 public constant MAX_BOARD_SIZE = 32;

    enum Direction {
        Up,
        Down,
        Left,
        Right
    }

    enum Operation {
        Add,
        Subtract,
        Multiply,
        Divide
    }

    struct Position {
        uint8 x;
        uint8 y;
    }

    struct SnakeGame {
        uint8 width;
        uint8 height;
        Direction direction;
        Position[] body;
        Position apple;
        uint256 score;
        bool active;
    }

    mapping(address => SnakeGame) private games;

    event GameStarted(address indexed player, uint8 width, uint8 height);
    event GameUpdated(address indexed player, Position head, bool ateApple, uint256 score);
    event GameOver(address indexed player, uint256 finalScore);
    event AppleSpawned(address indexed player, Position apple);
    event CalculatorUsed(
        address indexed player,
        Operation operation,
        int256 left,
        int256 right,
        int256 result,
        uint256 bonus
    );

    error InvalidBoardSize();
    error GameNotActive();
    error EmptySnake();

    /// @notice Starts a new game, overriding any previous state for the caller.
    /// @dev The snake is spawned horizontally in the center moving to the right.
    function startGame(uint8 width, uint8 height) external {
        if (width < MIN_BOARD_SIZE || height < MIN_BOARD_SIZE || width > MAX_BOARD_SIZE || height > MAX_BOARD_SIZE) {
            revert InvalidBoardSize();
        }

        SnakeGame storage game = games[msg.sender];
        delete game.body;

        game.width = width;
        game.height = height;
        game.direction = Direction.Right;
        game.score = 0;
        game.active = true;

        uint8 centerX = width / 2;
        uint8 centerY = height / 2;

        // spawn a snake with length 3 moving to the right
        game.body.push(Position(centerX - 1, centerY));
        game.body.push(Position(centerX, centerY));
        game.body.push(Position(centerX + 1, centerY));

        game.apple = _spawnApple(game);

        emit GameStarted(msg.sender, width, height);
        emit AppleSpawned(msg.sender, game.apple);
    }

    /// @notice Returns lightweight game metadata for a player.
    function getGameMeta(address player)
        external
        view
        returns (uint8 width, uint8 height, Direction direction, Position memory apple, uint256 score, bool active)
    {
        SnakeGame storage game = games[player];
        return (game.width, game.height, game.direction, game.apple, game.score, game.active);
    }

    /// @notice Returns the full snake body for the caller.
    function getBody(address player) external view returns (Position[] memory body) {
        SnakeGame storage game = games[player];
        body = new Position[](game.body.length);
        for (uint256 i = 0; i < game.body.length; i++) {
            body[i] = game.body[i];
        }
    }

    /// @notice Moves the snake a single step. Passing a direction that is opposite to the
    /// current direction is ignored to mimic classic snake behaviour.
    /// @param desiredDirection The next direction. Use the same direction to keep moving forward.
    /// @return alive Whether the snake survived this step.
    /// @return newHead The new head position.
    /// @return ateApple Whether the snake consumed the apple during this step.
    function move(Direction desiredDirection) external returns (bool alive, Position memory newHead, bool ateApple) {
        SnakeGame storage game = games[msg.sender];
        if (!game.active) {
            revert GameNotActive();
        }

        if (!_isOpposite(game.direction, desiredDirection)) {
            game.direction = desiredDirection;
        }

        (alive, newHead, ateApple) = _step(game);
        if (!alive) {
            game.active = false;
            emit GameOver(msg.sender, game.score);
        } else {
            emit GameUpdated(msg.sender, newHead, ateApple, game.score);
        }
    }

    /// @notice Performs a calculator operation.
    /// @dev If the player has an active game and the calculation result is non-zero, the score is boosted.
    function calculateAndBoost(int256 left, int256 right, Operation op) external returns (int256 result) {
        result = _calculate(left, right, op);

        SnakeGame storage game = games[msg.sender];
        uint256 bonus;
        if (game.active && result != 0) {
            uint256 magnitude = uint256(_abs(result));
            bonus = (magnitude % 5) + 1; // 1 to 5 extra points
            game.score += bonus;
        }

        emit CalculatorUsed(msg.sender, op, left, right, result, bonus);
    }

    /// @notice Pure calculator helper when you are not interested in the snake boosts.
    function calculate(int256 left, int256 right, Operation op) external pure returns (int256) {
        return _calculate(left, right, op);
    }

    function _step(SnakeGame storage game) private returns (bool alive, Position memory newHead, bool ateApple) {
        if (game.body.length == 0) {
            revert EmptySnake();
        }

        Position memory head = game.body[game.body.length - 1];
        newHead = head;
        if (game.direction == Direction.Up) {
            if (head.y == 0) return (false, newHead, false);
            newHead.y -= 1;
        } else if (game.direction == Direction.Down) {
            if (head.y + 1 >= game.height) return (false, newHead, false);
            newHead.y += 1;
        } else if (game.direction == Direction.Left) {
            if (head.x == 0) return (false, newHead, false);
            newHead.x -= 1;
        } else {
            if (head.x + 1 >= game.width) return (false, newHead, false);
            newHead.x += 1;
        }

        // check collision with body
        for (uint256 i = 0; i < game.body.length; i++) {
            if (game.body[i].x == newHead.x && game.body[i].y == newHead.y) {
                return (false, newHead, false);
            }
        }

        game.body.push(newHead);

        if (newHead.x == game.apple.x && newHead.y == game.apple.y) {
            game.score += 1;
            ateApple = true;
            game.apple = _spawnApple(game);
            emit AppleSpawned(msg.sender, game.apple);
        } else {
            // remove tail
            for (uint256 j = 0; j < game.body.length - 1; j++) {
                game.body[j] = game.body[j + 1];
            }
            game.body.pop();
        }

        alive = true;
    }

    function _spawnApple(SnakeGame storage game) private view returns (Position memory) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(block.prevrandao, block.timestamp, msg.sender, game.score, game.body.length)
            )
        );

        Position memory candidate;
        bool collision;
        uint256 attempts = 0;

        do {
            candidate = Position(uint8(seed % game.width), uint8((seed >> 8) % game.height));
            collision = false;
            for (uint256 i = 0; i < game.body.length; i++) {
                if (game.body[i].x == candidate.x && game.body[i].y == candidate.y) {
                    collision = true;
                    seed = uint256(keccak256(abi.encodePacked(seed, i)));
                    break;
                }
            }
            attempts++;
        } while (collision && attempts < 32);

        if (collision) {
            candidate = Position(0, 0);
        }

        return candidate;
    }

    function _calculate(int256 left, int256 right, Operation op) private pure returns (int256) {
        if (op == Operation.Add) {
            return left + right;
        } else if (op == Operation.Subtract) {
            return left - right;
        } else if (op == Operation.Multiply) {
            return left * right;
        }

        if (right == 0) {
            revert("Division by zero");
        }
        return left / right;
    }

    function _isOpposite(Direction a, Direction b) private pure returns (bool) {
        return (a == Direction.Up && b == Direction.Down)
            || (a == Direction.Down && b == Direction.Up)
            || (a == Direction.Left && b == Direction.Right)
            || (a == Direction.Right && b == Direction.Left);
    }

    function _abs(int256 value) private pure returns (int256) {
        return value >= 0 ? value : -value;
    }
}
