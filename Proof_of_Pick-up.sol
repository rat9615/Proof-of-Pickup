/*************************************************************************
 * Based on:
 * Title : POD_PhysicalItems
 * Author : Salah, Khaled and Hasan, Haya
 * Date : 2019
 * Availability: https://github.com/smartcontract694/POD_PhysicalItems
*************************************************************************/
pragma solidity 0.4.10;

//Contract for Proof of Pickup of Physical Asset
contract PoP {
    //Actors involved in the contract.
    //Customer deploys the contract.
    //Arbitrator handles disputes.
        address public customer;
        address public seller;
        address public carrier;
        address public arbitrator;
    
    mapping(address => bool) cancancelorder;
   //Charges of pickup and asset
       uint public pickupcharges;
       uint public assetprice;
       bytes32 assetid;
   
   mapping(address => bytes32) verification;
   
   //Factors concerning proof of pickup
       uint pickup_duration;
       uint carrier_pickuptime_onstart;
       uint seller_verification_time;
       uint carrier_entered_keys_start;
    
    enum PoPState
    {
        Withdraw_Money_From_Customer, Money_Withdrawn, Key_given_to_Carrier, Pickup_On_Way, Key_given_to_Seller, Arrived_To_Destination, Seller_Entered_Keys, Payment_Settled,
        Dispute_Failure, Refund, Abort
    }
    PoPState public state;
    
    //Constructor
    function PoP()
    {
       //Addresses of actors
       customer = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c;
       seller = 0x14723A09ACff6D2A60DcdF7aA4AFf308FDDC160C;
       carrier = 0x4B0897b0513fdC7C541B6d9D7E929C4e5364D2dB;
       arbitrator = 0x583031D1113aD414F02576BD6afaBfb302140225;
       //Initializing the data 
       assetprice = 2 ether;
       pickupcharges =  (10 * assetprice)/100;
       pickup_duration = 2 hours;
       seller_verification_time = 15 minutes;
       //ID(Randomly)
       assetid = 0xa41d333de1ef4f2eee356512d9ac81d7bdb174afcfca62e67fe598b5a187b533;
       cancancelorder[customer] = true;
       cancancelorder[seller] = true;
       cancancelorder[carrier] = true;
       state = PoPState.Withdraw_Money_From_Customer;
    }
    
    //Restrictions
    modifier deposit()
    {
        require(msg.value == assetprice + pickupcharges);
        _;
    }
    
    modifier Customer()
    {
        require(msg.sender == customer);
        _;
    }
    
    modifier Seller()
    {
        require(msg.sender == seller);
        _;
    }
    
    modifier Carrier()
    {
        require(msg.sender == carrier);
        _;
    }
    
    modifier Customer_Carrier_Seller
    {
        require(msg.sender == customer || msg.sender == carrier || msg.sender == seller);
        _;
    }
    
    event Charges_Withdrawn_From_Customer(string notification, address actor);
    event cancelreason(address actor, string notification, string reason);
    event Key_given_to_Seller(string notification, address actor);
    event Key_given_to_Carrier(string notification, address actor);
    event Pickup_On_Way(string notification, address actor);
    event Arrived_To_Destination( address actor,string notification);
    event Seller_Entered_Keys(address actor, string notification);
    event Seller_exceeded_verification_time(string notification, address actor);
    event Verification_Successful(string notification);
    event Verification_Failure(string notification);
    event refundrequest(string notification, address entity);
    
    //Customer deposits charges into the Contract (assetprice and deliverycharges)
    function Customer_Money_Withdrawal() payable deposit Customer
    {
        require(state == PoPState.Withdraw_Money_From_Customer);
        Charges_Withdrawn_From_Customer("Money has been successfully withdrawn from ", msg.sender);
        state = PoPState.Money_Withdrawn;
    }
    
    //Cancellation of the pickup by all the actors
    function CancelOrder(string reason)  Customer_Carrier_Seller
    {
        require(cancancelorder[msg.sender] == true);
        //Customer is refunded
        customer.transfer(assetprice + pickupcharges);
        cancelreason(msg.sender, "has cancelled the order due to", reason);
        state = PoPState.Abort;
        selfdestruct(msg.sender);
    }
    
    //customer or carrier can cancel the order as long as the key is not created.
    //seller can cancel the order as long as the key is not given to the carrier.
    function create_key_to_carrier() Customer returns (string)
    {
        require(state == PoPState.Money_Withdrawn);
        Key_given_to_Carrier("Key created and given to Carrier by ", msg.sender);
        cancancelorder[msg.sender] = false;
        cancancelorder[carrier] = false;
        state = PoPState.Key_given_to_Carrier;
        return "0xa41d333de1ef4f2eee356512d9ac81";
    }
    
    //Begin pickup of asset by Carrier
    function pickuppackage() Carrier 
    {
        require(state == PoPState.Key_given_to_Carrier);
        //Start pickup pickuptime 
        carrier_pickuptime_onstart = block.timestamp;
        cancancelorder[seller] = false;
        Pickup_On_Way("Pickup is on the way by ", msg.sender);
        state = PoPState.Pickup_On_Way;
    }
    
    //Create key and give to seller when pickup is on way
    function create_key_to_seller() Customer returns (string)
    {
        require(state == PoPState.Pickup_On_Way);
        Key_given_to_Seller("Key created and given to Seller by ", msg.sender);
        state = PoPState.Key_given_to_Seller;
        return "0xd7bdb174afcfca62e67fe598b5a187b533";
    }
    
    //Verify keys by Seller and Carrier 
    function verify_Carrier_Key(string keyC, string keyS) Carrier 
    {
        require(state == PoPState.Key_given_to_Seller);
        Arrived_To_Destination(msg.sender,"has arrived to Destination and has entered keys");
        verification[msg.sender] = keccak256(keyC,keyS);
        state = PoPState.Arrived_To_Destination;
        carrier_entered_keys_start = block.timestamp;
        
    }
    
    function verify_Seller_Key(string keyC, string keyS) Seller
    {
        require(state == PoPState.Arrived_To_Destination);
        Seller_Entered_Keys(msg.sender,"gives asset, entered keys");
        verification[msg.sender] = keccak256(keyC,keyS);
        state = PoPState.Seller_Entered_Keys;
        //call for internal function verify;
        verify();
    }
    
    function Sellerverification_time_exceeded() Carrier
    {
        require(block.timestamp > carrier_entered_keys_start + seller_verification_time && state == PoPState.Arrived_To_Destination);
        Seller_exceeded_verification_time("Seller has exceeded verification time, Dispute", msg.sender);
        verify();
    }
    
    //verify success or dispute
    function verify() 
    {
        require(state == PoPState.Seller_Entered_Keys);
        if(verification[carrier] == verification[seller])
        {
            Verification_Successful("Successful Verification, Payment is being settled");
            carrier.transfer(pickupcharges);
            seller.transfer(assetprice);
            state = PoPState.Payment_Settled;
        }
        else
        {
            Verification_Failure("Verification Failed. All ether transferred to arbitrator");
            state = PoPState.Dispute_Failure;
            arbitrator.transfer(this.balance);
            state = PoPState.Abort;
            selfdestruct(msg.sender);
        }
    }
    
    //Refund in case of exceeded pickup_duration
    function refund() Customer
    {
        require(block.timestamp > carrier_pickuptime_onstart + pickup_duration && state == PoPState.Pickup_On_Way);
        state = PoPState.Refund;
        refundrequest("Pickup Duration exceeded, Refund request", msg.sender);
        customer.transfer(assetprice + pickupcharges);
        state = PoPState.Abort;
        selfdestruct(msg.sender);
    }
}