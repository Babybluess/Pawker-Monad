// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Pawker is ERC721, ERC721URIStorage, Ownable {
    string private baseURI;
    // Constructor to initialize the contract with token details, base uri and owner
    constructor(address _owner, string memory _baseURI) ERC721("Pawker", "PAW") Ownable(_owner) {
        baseURI = _baseURI;
    }

    enum Status {
        CREATED,
        CANCELLED,
        INPROGRESS,
        COMPLETED
    }

    struct Tournament {
        address host;
        address diamond_address;
        address[] winners;
        uint256 initialize_amount;
        uint256 host_fee_amount;
        uint256 start_time;
        uint256 min_initialize_amount;
        uint256 ticket_price;
        uint256 system_fee;
        uint256[] reward_config;
        Status status;
    }

    function checkFund(address _address, address _tokenAddress, uint256 _tokenThresh) internal view returns (bool) {
        uint256 availableToken = IERC20(_tokenAddress).allowance(_address, address(this));

        if (availableToken < _tokenThresh) {
            return false;
        }
        
        return true;
    }

    Tournament[] public tournaments;
    
    mapping(uint256 => address[]) public tournament_participants;

    mapping(uint256 => mapping(address => uint256)) public participant_amount;

    mapping(address => bool) public isWhiteList;

    event CreateTournament(
        address host, 
        address diamond_address,
        address[] winners,
        uint256 initialize_amount,
        uint256 host_fee_amount,
        uint256 start_time,
        uint256 min_initialize_amount,
        uint256 ticket_price,
        uint256 system_fee,
        uint256[] reward_config,
        Status status
    );
    event BuyTicket(uint256 _tournament_id);
    event JoinTournament(uint256 _tournament_id, uint256 _participant_fee, uint256 _token_id);
    event OnboardTournament(uint256 _tournament_id);
    event UpdateWinners(uint256 _tournament_id, address[] winners);
    event FinishTournament(uint256 _tournament_id);
    event ClaimReward(uint256 _tournament_id);
    event ClaimTicketRefund(uint256 nft_id , uint256 _tournament_id);
    event Received(address sender, uint256 amount, string message);

        function setWhileList(address _whileList) external onlyOwner {
        require(_whileList != address(0), "Invalid address");

        isWhiteList[_whileList] = true;
    }

    modifier tournamentExists(uint256 _tournament_id) {
        require(_tournament_id < tournaments.length, "Invalid tournament id");
        _;  
    }

    modifier isInWhitelist(address _address) {
        require(isWhiteList[_address], "Invalid address");
        _;
    }

    function createTournament(address token_address, uint256[6] memory _fee_info, uint256[] memory _reward_config) external isInWhitelist(msg.sender) {
        bool isValidFund = checkFund(msg.sender, token_address, _fee_info[4]);

        require(isValidFund, "Insufficient allowance funds");

        tournaments.push(Tournament({
            host: msg.sender,
            diamond_address: token_address,
            winners: new address[](0),
            initialize_amount: _fee_info[0],
            host_fee_amount: _fee_info[1],
            start_time: _fee_info[2] + block.timestamp,
            min_initialize_amount: _fee_info[3],
            ticket_price: _fee_info[4],
            system_fee: _fee_info[5],
            reward_config: _reward_config,
            status: Status.CREATED
        }));       

        IERC20(token_address).transferFrom(msg.sender, address(this), _fee_info[4]);

        emit CreateTournament(
            msg.sender,
            token_address,
            new address[](0),
            _fee_info[0],
            _fee_info[1],
            _fee_info[2],
            _fee_info[3],
            _fee_info[4],
            _fee_info[5],
            _reward_config,
            Status.CREATED
        );
    }

    function buyTicket(uint256 _tournament_id) external payable tournamentExists(_tournament_id) {
        Tournament storage tournament = tournaments[_tournament_id];
        bool isValidFund = checkFund(msg.sender, tournament.diamond_address, tournament.ticket_price);

        require(isValidFund, "Insufficient allowance funds");
        require(tournament.start_time > block.timestamp, "Tournament already started");
        require(tournament.status == Status.CREATED, "Tournament already ended or in progress");
        require(msg.value == tournament.ticket_price, "Invalid ticket price");

        participant_amount[_tournament_id][msg.sender] = msg.value;

        IERC20(tournament.diamond_address).transferFrom(msg.sender, address(this), tournament.ticket_price);
        _safeMint(msg.sender, _tournament_id);

        emit BuyTicket(_tournament_id);
    }

    function joinTournament(uint256 _tournament_id, uint256 _participant_fee, uint256 _token_id) external tournamentExists(_tournament_id) {
        Tournament storage tournament = tournaments[_tournament_id];
         bool isValidFund = checkFund(msg.sender, tournament.diamond_address, _participant_fee);

        require(isValidFund, "Insufficient allowance funds");
        require(tournaments[_tournament_id].start_time > block.timestamp, "Tournament already started");
        require(tournaments[_tournament_id].status == Status.CREATED, "Tournament already ended");

        tournament_participants[_tournament_id].push(msg.sender);

        IERC20(tournament.diamond_address).transferFrom(msg.sender, address(this), _participant_fee);

        _burn(_token_id);

        emit JoinTournament(_tournament_id, _participant_fee, _token_id);
    }

    function onboardTournament(uint256 _tournament_id) external tournamentExists(_tournament_id) {
        Tournament storage tournament = tournaments[_tournament_id];

        require(tournaments[_tournament_id].start_time <= block.timestamp, "Tournament have not started");
        require(tournaments[_tournament_id].status == Status.CREATED, "Tournament already ended");

        tournament.status = Status.INPROGRESS;

        emit OnboardTournament(_tournament_id);
    }

    function updateWinners(uint256 _tournament_id, address[] memory winners) external tournamentExists(_tournament_id) {

        require(tournaments[_tournament_id].start_time < block.timestamp, "Tournament have not started");
        require(tournaments[_tournament_id].status == Status.INPROGRESS, "Tournament already ended");

        Tournament storage tournament = tournaments[_tournament_id];
        tournament.winners = winners;

        emit UpdateWinners(_tournament_id, winners);
    }

    function finishTournament(uint256 _tournament_id) external tournamentExists(_tournament_id) {
        require(tournaments[_tournament_id].start_time < block.timestamp, "Tournament have not started");
        require(tournaments[_tournament_id].status == Status.INPROGRESS, "Tournament already ended");

         Tournament storage tournament = tournaments[_tournament_id];
         tournament.status = Status.COMPLETED;

         emit FinishTournament(_tournament_id);
    }

    // function claimReward(uint256 _tournament_id) external tournamentExists(_tournament_id) {
    //     require(tournaments[_tournament_id].status == Status.COMPLETED, "Tournament not completed");

    //     Tournament storage tournament = tournaments[_tournament_id];
    //     uint256 winners_amount = tournament.winners.length();

    //     for (uint256 i = 0; i < winners_amount;) {
    //         uint256 reward = tournament.reward_config[i];
    //         if (reward != 0 && tournament.winners[i] == msg.sender) {
    //             IERC20(tournament.diamond_address).transfer(msg.sender, reward);
                
    //             break;
    //         }
    //     }

    //     emit ClaimReward(_tournament_id);
    // }

    function claimTicketRefund(uint256 nft_id , uint256 _tournament_id) external tournamentExists(_tournament_id) {
        require(ownerOf(nft_id) == msg.sender, "Invalid owner");

        Tournament storage tournament = tournaments[_tournament_id];

        IERC20(tournament.diamond_address).transfer(msg.sender, tournament.ticket_price);
        _burn(nft_id);

        emit ClaimTicketRefund(nft_id, _tournament_id);
    }

    // Function called when receiving BERA **without** data
    receive() external payable {
        emit Received(msg.sender, msg.value, "Receive function called");
    }

    // Function called when receiving BERA **with** data or for unknown functions
    fallback() external payable {
        emit Received(msg.sender, msg.value, "Fallback function called");
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}